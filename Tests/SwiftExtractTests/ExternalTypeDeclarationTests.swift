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
import Testing

@Suite("External type declarations")
struct ExternalTypeDeclarationSuite {

  @Test func externalTypesResolveDuringAnalysis() throws {
    let config = DefaultSwiftExtractConfiguration(
      swiftModule: "Aquarium",
      externalTypeDeclarations: [
        "FishKit": [
          ExternalTypeDeclaration(qualifiedName: ["Fish"], kind: .class),
          ExternalTypeDeclaration(qualifiedName: ["Fish", "Species"], kind: .enum),
          ExternalTypeDeclaration(
            qualifiedName: ["School"],
            kind: .struct,
            genericParameterNames: ["Member"]
          ),
        ]
      ]
    )

    let result = try analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          import FishKit

          public func adopt(_ fish: Fish) {}
          public func identify(_ fish: Fish) -> Fish.Species { fatalError() }
          public func gather(_ school: School<Fish>) {}
          """
        )
      ],
      moduleName: "Aquarium",
      config: config
    )

    let names = Set(result.extractedGlobalFuncs.map(\.name))
    #expect(names == ["adopt", "identify", "gather"])

    let identify = try #require(result.extractedGlobalFuncs.first { $0.name == "identify" })
    let resultDecl = try #require(identify.functionSignature.result.type.asNominalTypeDeclaration)
    #expect(resultDecl.name == "Species")
    #expect(resultDecl.moduleName == "FishKit")
  }

  @Test func combinesWithStringStubsForTheSameModule() throws {
    let config = DefaultSwiftExtractConfiguration(
      swiftModule: "Aquarium",
      importedModuleStubs: ["FishKit": ["public struct Coral {}"]],
      externalTypeDeclarations: [
        "FishKit": [ExternalTypeDeclaration(qualifiedName: ["Fish"], kind: .class)]
      ]
    )

    let result = try analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          import FishKit

          public func decorate(_ coral: Coral, home: Fish) {}
          """
        )
      ],
      moduleName: "Aquarium",
      config: config
    )

    #expect(result.extractedGlobalFuncs.map(\.name) == ["decorate"])
  }

  @Test func stubSourceReconstructsNesting() {
    let declarations = [
      ExternalTypeDeclaration(qualifiedName: ["Outer", "Inner"], kind: .struct),
      ExternalTypeDeclaration(qualifiedName: ["Lone"], kind: .protocol),
    ]
    let rendered = declarations.stubSourceDeclarations()
    #expect(
      rendered == [
        "public protocol Lone {}",
        """
        public enum Outer {
          public struct Inner {}
        }
        """,
      ]
    )
  }
}
