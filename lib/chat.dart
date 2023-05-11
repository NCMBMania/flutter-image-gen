import 'dart:convert';
import 'dart:io';
import 'dart:core';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:uuid/uuid.dart';
import 'package:ncmb/ncmb.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'dart:html' as webFile;

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  List<types.Message> _messages = [];

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Chat(
          messages: _messages,
          onSendPressed: _handleSendPressed,
          showUserAvatars: false,
          showUserNames: false,
          user: const types.User(
            id: 'user',
          ),
        ),
      );

  void _addMessage(types.Message message) {
    setState(() {
      _messages.insert(0, message);
    });
  }

  void _handleSendPressed(types.PartialText message) async {
    // メッセージを保存
    var obj = NCMBObject('ImageGen');
    obj.set('content', message.text);
    obj.set('role', 'user');
    await obj.save();
    final textMessage = toTextMessage(obj);
    _addMessage(textMessage);
    // OpenAIのAPIを呼び出す
    var script = NCMBScript('image.js').body('prompt', message.text);
    var res = (await script.post()) as Map<String, dynamic>;
    // OpenAIの返答を保存
    obj.set('image', res['fileName'] as String);
    await obj.save();
    final imageMessage = await toImageMessage(obj);
    _addMessage(imageMessage);
  }

  // NCMBObjectをTextMessageに変換する関数
  Future<List<types.Message>> toMessage(NCMBObject obj) async {
    var messages = <types.Message>[];
    var message = toTextMessage(obj);
    messages.add(message);
    var imageMessage = await toImageMessage(obj);
    messages.add(imageMessage);
    return messages.reversed.toList();
  }

  types.TextMessage toTextMessage(NCMBObject obj) {
    return types.TextMessage(
      author: types.User(id: obj.getString('role', defaultValue: 'user')),
      createdAt: obj.getDateTime('createDate').microsecondsSinceEpoch,
      id: "${obj.objectId}-text",
      text: obj.getString('content'),
    );
  }

  Future<types.ImageMessage> toImageMessage(NCMBObject obj) async {
    final imageName = obj.getString('image', defaultValue: '');
    final file = await NCMBFile.download(imageName);
    final blob = ByteData.sublistView(file.data);
    final path = webFile.Url.createObjectUrlFromBlob(webFile.Blob([blob]));
    return types.ImageMessage(
      author: types.User(id: obj.getString('role', defaultValue: 'assistant')),
      createdAt: obj.getDateTime('createDate').microsecondsSinceEpoch,
      id: "${obj.objectId}-image",
      name: imageName,
      height: 250,
      width: 250,
      size: file.data.length,
      uri: path, // uri.uri.toString(),
    );
  }

  void _loadMessages() async {
    // メッセージを取得するクエリを作成
    var query = NCMBQuery('ImageGen');
    // 1日前以降のメッセージを取得
    var date = DateTime.now().subtract(const Duration(days: 1));
    // query.greaterThanOrEqualTo('createDate', date);
    query.order('createDate', descending: true); // 古いデータが上に来るようにする
    var ary = (await query.fetchAll()).map((o) => o as NCMBObject).toList();
    // 取得したNCMBObjectのリストをTextMessageに変換
    final messages = await Future.wait(ary.map((e) => toMessage(e)));
    // メッセージを更新
    setState(() {
      _messages = messages.expand((l) => l).toList();
    });
  }
}
