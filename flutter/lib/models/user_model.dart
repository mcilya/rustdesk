import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../common.dart';
import 'model.dart';
import 'platform_model.dart';

class UserModel {
  var userName = ''.obs;
  WeakReference<FFI> parent;

  UserModel(this.parent) {
    try{
      login('1', '1');
    } catch(e) {
      debugPrint("${e}");
    }
    refreshCurrentUser();
  }

  void refreshCurrentUser() async {
    await getUserName();
    final token = bind.mainGetLocalOption(key: 'access_token');
    if (token == '') return;
    final url = await bind.mainGetApiServer();
    final body = {
      'uuid': await bind.mainGetUuid(),
      'username': await bind.mainGetLocalOption(key: 'company_name'),
      'password': await bind.mainGetLocalOption(key: 'company_pass'),
    };
      final response = await http.post(Uri.parse('$url/api/currentUser'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token'
          },
          body: json.encode(body));
      final status = response.statusCode;
      if (status == 401 || status == 400) {
        resetToken();
        return;
      }
      debugPrint(response.body);
    try {
      await _parseResp(response.body);
    } catch (e) {
      print('Failed to refreshCurrentUser: $e');
    }
  }

  void resetToken() async {
    await bind.mainSetLocalOption(key: 'access_token', value: '');
    await bind.mainSetLocalOption(key: 'user_info', value: '');
    userName.value = '';
  }

  Future<String> _parseResp(dynamic body) async {
    final data = json.decode(body);
    if (data.containsKey('error')) {
      return data['error'];
    }
    final token = data['access_token'];
    debugPrint(token);
    if (token != null) {
      await bind.mainSetLocalOption(key: 'access_token', value: token);
    }
    
    final info = Map<String, dynamic>.from(data['user']);
    if (info != null) {
      final value = json.encode(info);
      debugPrint(value);
      await bind.mainSetOption(key: 'user_info', value: value);
      userName.value = info['name'];
      bind.mainSetPermanentPassword(password: await bind.mainGetLocalOption(key: 'company_pass'));
      await bind.mainSetOption(key: "verification-method", value: 'use-permanent-password');
    }

    final conf = Map<String, dynamic>.from(data['conf']);
    if (conf != null) {
      await bind.mainSetOption(key: "relay-server", value: conf['relay-server']);
      await bind.mainSetOption(key: "custom-rendezvous-server", value: conf['relay-server']);
      await bind.mainSetOption(key: "key", value: conf['key']);
    }
    return '';
  }

  Future<String> getUserName() async {
    if (userName.isNotEmpty) {
      return userName.value;
    }
    final userInfo = bind.mainGetLocalOption(key: 'user_info');
    if (userInfo.trim().isEmpty) {
      return '';
    }
    final m = jsonDecode(userInfo);
    if (m == null) {
      userName.value = '';
    } else {
      userName.value = m['name'] ?? '';
    }
    return userName.value;
  }

  Future<void> logOut() async {
    final tag = gFFI.dialogManager.showLoading(translate('Waiting'));
    final url = await bind.mainGetApiServer();
    final _ = await http.post(Uri.parse('$url/api/logout'),
        body: {
          'id': await bind.mainGetMyId(),
          'uuid': await bind.mainGetUuid(),
        },
        headers: await getHttpHeaders());
    await Future.wait([
      bind.mainSetLocalOption(key: 'access_token', value: ''),
      bind.mainSetLocalOption(key: 'user_info', value: ''),
      bind.mainSetLocalOption(key: 'selected-tags', value: ''),
    ]);
    parent.target?.abModel.clear();
    userName.value = '';
    gFFI.dialogManager.dismissByTag(tag);
  }

  Future<Map<String, dynamic>> login(String userName, String pass) async {
    final url = await bind.mainGetApiServer();
    try {
      final resp = await http.post(Uri.parse('$url/api/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'username': await bind.mainGetLocalOption(key: 'company_name'),
            'password': await bind.mainGetLocalOption(key: 'company_pass'),
            'id': await bind.mainGetMyId(),
            'uuid': await bind.mainGetUuid(),
            'hostname': await bind.mainGetLocalOption(key: 'hostname'),
            'platform': await bind.mainGetLocalOption(key: 'platform')
          }));
      final body = jsonDecode(resp.body);
      bind.mainSetLocalOption(
          key: 'access_token', value: body['access_token'] ?? '');
      bind.mainSetLocalOption(
          key: 'user_info', value: jsonEncode(body['user']));
      this.userName.value = body['user']?['name'] ?? '';
      return body;
    } catch (err) {
      return {'error': '$err'};
    }
  }
}
