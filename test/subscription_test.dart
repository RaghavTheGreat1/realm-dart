////////////////////////////////////////////////////////////////////////////////
//
// Copyright 2022 Realm Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
////////////////////////////////////////////////////////////////////////////////

import 'dart:io';

import 'package:test/expect.dart';

import '../lib/realm.dart';
import 'test.dart';

Future<void> main([List<String>? args]) async {
  print("Current PID $pid");

  await setupTests(args);

  baasTest('Get subscriptions', (configuration) async {
    final app = App(configuration);
    final credentials = Credentials.anonymous();
    final user = await app.logIn(credentials);
    final realm = getRealm(Configuration.flexibleSync(user, [Task.schema]));

    expect(realm.subscriptions, isEmpty);

    final query = realm.all<Task>();

    realm.subscriptions!.update((mutableSet) {
      mutableSet.addOrUpdate(query);
    });

    expect(realm.subscriptions!.length, 1);

    realm.subscriptions!.update((mutableSet) {
      mutableSet.remove(query);
    });

    expect(realm.subscriptions, isEmpty);

    final name = 'a random name';
    realm.subscriptions!.update((mutableSet) {
      mutableSet.addOrUpdate(query, name: name);
    });

    expect(realm.subscriptions!.findByName(name), isNotNull);

    realm.subscriptions!.update((mutableSet) {
      mutableSet.removeByName(name);
    });

    expect(realm.subscriptions, isEmpty);
    // expect(realm.subscriptions!.findByName(name), isNull);

    realm.close();
    app.logout(user);
  });
}
