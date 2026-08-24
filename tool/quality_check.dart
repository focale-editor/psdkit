/// Checks documentation coverage and class-member ordering in library sources.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Audits every Dart source below `lib` and sets a failing exit code on issues.
Future<void> main() async {
  final List<File> files = await Directory('lib').list(recursive: true).where((entity) => entity is File && entity.path.endsWith('.dart')).cast<File>().toList();
  files.sort((left, right) => left.path.compareTo(right.path));
  final List<String> issues = <String>[];
  for (final File file in files) {
    final String source = await file.readAsString();
    final _QualityVisitor visitor = _QualityVisitor(path: file.path, source: source);
    parseString(content: source, path: file.path, throwIfDiagnostics: false).unit.accept(visitor);
    issues.addAll(visitor.issues);
  }
  issues.forEach(stderr.writeln);
  if (issues.isNotEmpty) {
    stderr.writeln('${issues.length} documentation or member-order issue(s).');
    exitCode = 1;
  }
}

/// Finds undocumented declarations and misplaced class members.
final class _QualityVisitor extends RecursiveAstVisitor<void> {
  /// Path displayed in diagnostics.
  final String path;

  /// Source used to compute one-based line numbers.
  final String source;

  /// Diagnostics collected during traversal.
  final List<String> issues = <String>[];

  /// Creates a visitor for one source file.
  _QualityVisitor({required this.path, required this.source});

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    _checkDocumentation(node);
    _checkOrder(node.body.members);
    super.visitClassDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    _checkDocumentation(node);
    super.visitConstructorDeclaration(node);
  }

  @override
  void visitEnumConstantDeclaration(EnumConstantDeclaration node) {
    _checkDocumentation(node);
    super.visitEnumConstantDeclaration(node);
  }

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    _checkDocumentation(node);
    _checkOrder(node.body.members);
    super.visitEnumDeclaration(node);
  }

  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {
    _checkDocumentation(node);
    super.visitExtensionDeclaration(node);
  }

  @override
  void visitExtensionTypeDeclaration(ExtensionTypeDeclaration node) {
    _checkDocumentation(node);
    _checkOrder(node.body.members);
    super.visitExtensionTypeDeclaration(node);
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    _checkDocumentation(node);
    super.visitFieldDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.parent is CompilationUnit) {
      _checkDocumentation(node);
    }
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (!node.metadata.any((annotation) => annotation.name.name == 'override')) {
      _checkDocumentation(node);
    }
    super.visitMethodDeclaration(node);
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    _checkDocumentation(node);
    _checkOrder(node.body.members);
    super.visitMixinDeclaration(node);
  }

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    _checkDocumentation(node);
    super.visitTopLevelVariableDeclaration(node);
  }

  /// Records a diagnostic when [node] has no Dartdoc comment.
  void _checkDocumentation(AnnotatedNode node) {
    if (node.documentationComment == null) {
      issues.add('$path:${_line(node.offset)}: missing Dartdoc for ${node.runtimeType}');
    }
  }

  /// Enforces fields, then constructors, then methods within [members].
  void _checkOrder(List<ClassMember> members) {
    int previousRank = 0;
    for (final ClassMember member in members) {
      final int rank = switch (member) {
        FieldDeclaration() => 1,
        ConstructorDeclaration() => 2,
        MethodDeclaration() => 3,
        _ => 3,
      };
      if (rank < previousRank) {
        issues.add('$path:${_line(member.offset)}: members must be ordered as fields, constructors, then methods');
      }
      previousRank = rank;
    }
  }

  /// Returns the one-based line containing [offset].
  int _line(int offset) => '\n'.allMatches(source.substring(0, offset)).length + 1;
}
