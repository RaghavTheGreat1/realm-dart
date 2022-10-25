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

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:realm_common/realm_common.dart';
import 'package:source_gen/source_gen.dart';
import 'annotation_value.dart';
import 'error.dart';
import 'field_element_ex.dart';

import 'element.dart';
import 'realm_field_info.dart';
import 'realm_model_info.dart';
import 'type_checkers.dart';
import 'session.dart';

extension on Iterable<FieldElement> {
  Iterable<RealmFieldInfo> get realmInfo sync* {
    final primaryKeys = <RealmFieldInfo>[];
    for (final f in this) {
      final info = f.realmInfo;
      if (info == null) continue;
      if (info.isPrimaryKey) {
        primaryKeys.add(info);
      }
      yield info;
    }
    if (primaryKeys.length > 1) {
      final key = primaryKeys[1];
      final field = key.fieldElement;
      final annotation = field.primaryKeyInfo!.annotation;
      throw RealmInvalidGenerationSourceError(
        'Duplicate primary keys',
        todo: "Avoid duplicated $annotation on fields ${primaryKeys.map((e) => "'$e'").join(', ')}",
        element: field,
        primarySpan: field.span!,
        primaryLabel: 'second primary key',
        secondarySpans: {
          ...{for (final p in primaryKeys..removeAt(1)) p.fieldElement.span!: ''},
        },
      );
    }
  }
}

extension ClassElementEx on ClassElement {
  ClassDeclaration get declarationAstNode => getDeclarationFromElement(this)!.node as ClassDeclaration;

  AnnotationValue? get realmModelInfo => annotationInfoOfExact(realmModelChecker);

  RealmModelInfo? get realmInfo {
    try {
      final modelInfo = realmModelInfo;
      if (modelInfo == null) {
        return null;
      }

      final modelName = this.name;

      // ensure a valid prefix and suffix is used.
      final prefix = session.prefix;
      var suffix = session.suffix;
      if (!modelName.startsWith(prefix)) {
        throw RealmInvalidGenerationSourceError(
          'Missing prefix on realm model name',
          element: this,
          primarySpan: span,
          primaryLabel: 'missing prefix',
          todo: 'Align class name to match prefix ${prefix is RegExp ? '${prefix.pattern} (regular expression)' : prefix},',
        );
      }

      if (!modelName.endsWith(suffix)) {
        throw RealmInvalidGenerationSourceError('Missing suffix on realm model name',
            element: this, primarySpan: span, primaryLabel: 'missing suffix', todo: 'Align class name to have suffix $suffix,');
      }

      // Remove suffix and prefix, if any.
      final name = modelName.substring(0, modelName.length - suffix.length).replaceFirst(prefix, '');

      // Check that mapping not already defined
      final mapped = session.mapping.putIfAbsent(name, () => this);
      if (mapped != this) {
        throw RealmInvalidGenerationSourceError('Duplicate definition',
            element: this,
            primarySpan: span,
            primaryLabel: "realm model '${mapped.displayName}' already defines '$name'",
            secondarySpans: {
              mapped.span!: '',
            },
            todo: "Duplicate realm model definitions '$displayName' and '${mapped.displayName}'.");
      }

      // Check that realm model class does not extend another class than Object (not supported for now).
      if (supertype != session.typeProvider.objectType) {
        throw RealmInvalidGenerationSourceError(
          'Realm model classes can only extend Object',
          primarySpan: span,
          primaryLabel: 'cannot extend $supertype',
          todo: '',
          element: this,
        );
      }

      // Check that no constructor is defined.
      final explicitCtors = constructors.where((c) => !c.isSynthetic);
      if (explicitCtors.isNotEmpty) {
        final ctor = explicitCtors.first;
        throw RealmInvalidGenerationSourceError(
          'No constructors allowed on realm model classes',
          element: ctor,
          primarySpan: ctor.span,
          primaryLabel: 'has constructor',
          todo: 'Remove constructor',
        );
      }

      final realmName = remappedRealmName ?? name;

      // Core has a limit of 57 characters for SDK names (technically 63, but SDKs names are always prefixed class_)
      if (realmName.length > 57) {
        final clarification = realmName == name ? '' : ' which is stored as $realmName';
        throw RealmInvalidGenerationSourceError(
          "Invalid model name",
          element: this,
          primarySpan: span,
          primaryLabel: "$realmName is too long (> 57 characters)",
          todo: //
              '$name$clarification is too long (${realmName.length} characters when max is 57). '
              'Either rename it to something shorter or use the @MapTo annotation.',
        );
      }

      final objectType = ObjectType.values[modelInfo.value.getField('type')!.getField('index')!.toIntValue()!];

      final mappedFields = fields.realmInfo.toList();

      if (objectType == ObjectType.embeddedObject && mappedFields.any((field) => field.isPrimaryKey)) {
        final pkSpan = fields.firstWhere((field) => field.realmInfo?.isPrimaryKey == true).span;
        throw RealmInvalidGenerationSourceError("Primary key not allowed on embedded objects",
            element: this,
            primarySpan: pkSpan,
            secondarySpans: {span!: ''},
            primaryLabel: "$realmName is marked as embedded but has primary key defined",
            todo: 'Remove the @PrimaryKey annotation from the field or set the model type to a value different from ObjectType.embeddedObject.');
      }

      return RealmModelInfo(name, modelName, realmName, mappedFields, objectType);
    } on InvalidGenerationSourceError catch (_) {
      rethrow;
    } catch (e, s) {
      // Fallback. Not perfect, but better than just forwarding original error.
      throw RealmInvalidGenerationSourceError(
        '$e \n $s',
        todo: //
            'Unexpected error. Please open an issue on: '
            'https://github.com/realm/realm-dart',
        element: this,
      );
    }
  }
}
