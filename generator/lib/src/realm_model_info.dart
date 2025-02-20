////////////////////////////////////////////////////////////////////////////////
//
// Copyright 2021 Realm Inc.
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

import 'package:realm_common/realm_common.dart';

import 'dart_type_ex.dart';
import 'field_element_ex.dart';
import 'realm_field_info.dart';

class RealmModelInfo {
  final String name;
  final String modelName;
  final String realmName;
  final List<RealmFieldInfo> fields;
  final ObjectType baseType;

  const RealmModelInfo(this.name, this.modelName, this.realmName, this.fields, this.baseType);

  Iterable<String> toCode() sync* {
    yield 'class $name extends $modelName with RealmEntity, RealmObjectBase, ${baseType.className} {';
    {
      final allSettable = fields.where((f) => !f.type.isRealmCollection && !f.isRealmBacklink).toList();

      final hasDefaults = allSettable.where((f) => f.hasDefaultValue).toList();
      if (hasDefaults.isNotEmpty) {
        yield 'static var _defaultsSet = false;';
        yield '';
      }

      yield '$name(';
      {
        final required = allSettable.where((f) => f.isRequired || f.isPrimaryKey);
        yield* required.map((f) => '${f.mappedTypeName} ${f.name},');

        final notRequired = allSettable.where((f) => !f.isRequired && !f.isPrimaryKey);
        final collections = fields.where((f) => f.isRealmCollection && !f.isDartCoreSet).toList();
        final sets = fields.where((f) => f.isDartCoreSet).toList();
        if (notRequired.isNotEmpty || collections.isNotEmpty || sets.isNotEmpty) {
          yield '{';
          yield* notRequired.map((f) => '${f.mappedTypeName} ${f.name}${f.initializer},');
          yield* collections.map((c) => 'Iterable<${c.type.basicMappedName}> ${c.name}${c.initializer},');
          yield* sets.map((c) => 'Set<${c.type.basicMappedName}> ${c.name}${c.initializer},');
          yield '}';
        }

        yield ') {';

        if (hasDefaults.isNotEmpty) {
          yield 'if (!_defaultsSet) {';
          yield '  _defaultsSet = RealmObjectBase.setDefaults<$name>({';
          yield* hasDefaults.map((f) => "'${f.realmName}': ${f.fieldElement.initializerExpression},");
          yield '  });';
          yield '}';
        }

        yield* allSettable.map((f) {
          return "RealmObjectBase.set(this, '${f.realmName}', ${f.name});";
        });

        yield* collections.map((c) {
          return "RealmObjectBase.set<${c.mappedTypeName}>(this, '${c.realmName}', ${c.mappedTypeName}(${c.name}));";
        });

        yield* sets.map((c) {
          return "RealmObjectBase.set<${c.mappedTypeName}>(this, '${c.realmName}', ${c.mappedTypeName}(${c.name}));";
        });
      }
      yield '}';
      yield '';
      yield '$name._();';
      yield '';

      yield* fields.expand((f) => [
            ...f.toCode(),
            '',
          ]);

      yield '@override';
      yield 'Stream<RealmObjectChanges<$name>> get changes => RealmObjectBase.getChanges<$name>(this);';
      yield '';

      yield '@override';
      yield '$name freeze() => RealmObjectBase.freezeObject<$name>(this);';
      yield '';

      yield 'static SchemaObject get schema => _schema ??= _initSchema();';
      yield 'static SchemaObject? _schema;';
      yield 'static SchemaObject _initSchema() {';
      {
        yield 'RealmObjectBase.registerFactory($name._);';
        yield "return const SchemaObject(ObjectType.${baseType.name}, $name, '$realmName', [";
        {
          yield* fields.map((f) {
            final namedArgs = {
              if (f.name != f.realmName) 'mapTo': f.realmName,
              if (f.optional) 'optional': f.optional,
              if (f.isPrimaryKey) 'primaryKey': f.isPrimaryKey,
              if (f.indexed) 'indexed': f.indexed,
              if (f.realmType == RealmPropertyType.object) 'linkTarget': f.basicRealmTypeName,
              if (f.realmType == RealmPropertyType.linkingObjects) ...{
                'linkOriginProperty': f.linkOriginProperty!,
                'collectionType': RealmCollectionType.list,
                'linkTarget': f.basicRealmTypeName,
              },
              if (f.realmCollectionType != RealmCollectionType.none) 'collectionType': f.realmCollectionType,
            };
            return "SchemaProperty('${f.name}', ${f.realmType}${namedArgs.isNotEmpty ? ', ${namedArgs.toArgsString()}' : ''}),";
          });
        }
        yield ']);';
      }
      yield '}';
    }
    yield '}';
  }
}

extension<K, V> on Map<K, V> {
  String toArgsString() {
    return () sync* {
      for (final e in entries) {
        if (e.value is String) {
          yield "${e.key}: '${e.value}'";
        } else {
          yield '${e.key}: ${e.value}';
        }
      }
    }()
        .join(',');
  }
}
