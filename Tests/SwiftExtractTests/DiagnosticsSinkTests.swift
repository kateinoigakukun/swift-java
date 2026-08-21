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

import SwiftExtract
import SwiftSyntax
import Testing

@Suite("Diagnostics sink")
struct DiagnosticsSinkSuite {

  @Test func skippedDeclarationsAreReportedWithNodeAndFile() throws {
    let sink = CollectingDiagnosticsSink()
    let result = try analyze(
      sources: [
        (
          "/fake/Tank.swift",
          """
          public func fillTank(_ water: Water) {}
          public func drainTank() {}
          """
        ),
        (
          "/fake/Fish.swift",
          """
          public class Fish {
            public init(species: Species) {}
            public var home: Aquarium { fatalError() }
          }
          """
        ),
      ],
      moduleName: "Aquarium",
      diagnosticsSink: sink
    )

    // The resolvable declarations still extract.
    #expect(result.extractedGlobalFuncs.map(\.name) == ["drainTank"])
    #expect(result.extractedTypes["Fish"] != nil)

    // One event per skipped declaration, anchored to its node and file.
    #expect(sink.diagnostics.count == 3)
    for diagnostic in sink.diagnostics {
      #expect(diagnostic.kind == .skippedDeclaration)
      #expect(diagnostic.moduleName == "Aquarium")
      #expect(diagnostic.underlyingError != nil)
    }

    let byName = Dictionary(
      uniqueKeysWithValues: sink.diagnostics.map { ($0.declarationName, $0) }
    )
    let fillTank = try #require(byName["'fillTank(_:)'"])
    #expect(fillTank.sourceFilePath == "/fake/Tank.swift")
    #expect(fillTank.node.is(FunctionDeclSyntax.self))
    #expect(fillTank.message.contains("Failed to import"))

    let initializer = try #require(byName["Fish.init(species:)"])
    #expect(initializer.sourceFilePath == "/fake/Fish.swift")
    #expect(initializer.node.is(InitializerDeclSyntax.self))

    let variable = try #require(byName["Fish.home"])
    #expect(variable.sourceFilePath == "/fake/Fish.swift")
    #expect(variable.node.is(VariableDeclSyntax.self))
  }

  @Test func skippedExtensionsAreReported() throws {
    let sink = CollectingDiagnosticsSink()
    _ = try analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          extension NoSuchType {
            public func swim() {}
          }
          """
        )
      ],
      moduleName: "Aquarium",
      diagnosticsSink: sink
    )
    let diagnostic = try #require(sink.diagnostics.first)
    #expect(diagnostic.kind == .skippedDeclaration)
    #expect(diagnostic.node.is(ExtensionDeclSyntax.self))
    #expect(diagnostic.message.contains("NoSuchType"))
  }

  @Test func multipleBindingsExtractEachVariable() throws {
    let result = try analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          public class Tank {
            public var width: Int = 0, height: Int = 0
          }
          """
        )
      ],
      moduleName: "Aquarium"
    )
    let tank = try #require(result.extractedTypes["Tank"])
    let names = tank.variables.map(\.name)
    #expect(names == ["width", "width", "height", "height"])  // getter+setter each
  }

  @Test func noEventsWhenEverythingExtracts() throws {
    let sink = CollectingDiagnosticsSink()
    _ = try analyze(
      sources: [("/fake/Source.swift", "public func swim(distance: Int) {}")],
      moduleName: "Aquarium",
      diagnosticsSink: sink
    )
    #expect(sink.diagnostics.isEmpty)
  }
}
