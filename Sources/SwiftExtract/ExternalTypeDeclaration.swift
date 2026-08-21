//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift.org project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift.org project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// Describes a type that exists in another module, without access to that
/// module's source.
///
/// Consumers that keep their own serialized description of dependency modules
/// (e.g. a per-target intermediate representation produced by an earlier build
/// phase) can hand the analyzer the *shapes* of those types via
/// `SwiftExtractConfiguration.externalTypeDeclarations` so that references to
/// them resolve during analysis, instead of rendering Swift stub source
/// themselves (`importedModuleStubs`) or re-parsing dependency sources
/// (`SourceDependencies`).
public struct ExternalTypeDeclaration: Hashable {
  public enum Kind: String, Hashable {
    case `class`
    case `struct`
    case `enum`
    case `protocol`
    case actor
  }

  /// The type's name components from the module root, e.g. `["Outer", "Inner"]`
  /// for `DependencyModule.Outer.Inner`.
  public let qualifiedName: [String]

  public let kind: Kind

  /// Names of the type's generic parameters, if any.
  public let genericParameterNames: [String]

  public init(
    qualifiedName: [String],
    kind: Kind,
    genericParameterNames: [String] = []
  ) {
    precondition(!qualifiedName.isEmpty, "qualifiedName must have at least one component")
    self.qualifiedName = qualifiedName
    self.kind = kind
    self.genericParameterNames = genericParameterNames
  }
}

private final class ExternalTypeStubNode {
  var declaration: ExternalTypeDeclaration?
  var children: [String: ExternalTypeStubNode] = [:]
  var childOrder: [String] = []

  func child(_ name: String) -> ExternalTypeStubNode {
    if let existing = children[name] { return existing }
    let node = ExternalTypeStubNode()
    children[name] = node
    childOrder.append(name)
    return node
  }

  func render(name: String, indent: String) -> String {
    let kind = declaration?.kind.rawValue ?? "enum"
    let genericParameterNames = declaration?.genericParameterNames ?? []
    let genericClause =
      genericParameterNames.isEmpty ? "" : "<\(genericParameterNames.joined(separator: ", "))>"
    var source = "\(indent)public \(kind) \(name)\(genericClause) {"
    if childOrder.isEmpty {
      return source + "}"
    }
    for childName in childOrder {
      source += "\n" + children[childName]!.render(name: childName, indent: indent + "  ")
    }
    source += "\n\(indent)}"
    return source
  }
}

extension Collection where Element == ExternalTypeDeclaration {
  /// Render these declarations as Swift stub source for a synthetic module,
  /// reconstructing the nesting structure from the qualified names. Ancestor
  /// types that are not themselves declared are synthesized as `enum`
  /// namespaces.
  package func stubSourceDeclarations() -> [String] {
    let root = ExternalTypeStubNode()
    for declaration in self.sorted(by: { $0.qualifiedName.lexicographicallyPrecedes($1.qualifiedName) }) {
      var node = root
      for component in declaration.qualifiedName {
        node = node.child(component)
      }
      node.declaration = declaration
    }

    return root.childOrder.map { root.children[$0]!.render(name: $0, indent: "") }
  }
}
