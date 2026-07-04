//
//  FuzzyFileMatcherTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

final class FuzzyFileMatcherTests: XCTestCase {
    func testReturnsNilWhenQueryIsNotSubsequence() throws {
        var scorer = FuzzyFileScorer()
        let target = FuzzyMatchTarget(relativeParentPath: "Sources", fileName: "App.swift")
        let query = try XCTUnwrap(FuzzyQuery(rawQuery: "xyz"))

        XCTAssertNil(scorer.score(query, in: target))
        XCTAssertNil(scorer.scoreWithPositions(query, in: target))
    }

    func testPrefersCompactMatchOverScatteredMatch() throws {
        var scorer = FuzzyFileScorer()
        let target = FuzzyMatchTarget(relativeParentPath: "", fileName: "AxpxpApp.swift")
        let query = try XCTUnwrap(FuzzyQuery(rawQuery: "app"))

        let match = try XCTUnwrap(scorer.scoreWithPositions(query, in: target))

        XCTAssertEqual(match.positions, [5, 6, 7])
        XCTAssertEqual(scorer.score(query, in: target), match.score)
    }

    func testConsecutiveMatchOutscoresScatteredMatch() throws {
        var scorer = FuzzyFileScorer()
        let query = try XCTUnwrap(FuzzyQuery(rawQuery: "abc"))
        let consecutiveTarget = FuzzyMatchTarget(relativeParentPath: "", fileName: "abc.swift")
        let scatteredTarget = FuzzyMatchTarget(relativeParentPath: "", fileName: "a_b_c.swift")

        let consecutiveScore = try XCTUnwrap(scorer.score(query, in: consecutiveTarget))
        let scatteredScore = try XCTUnwrap(scorer.score(query, in: scatteredTarget))

        XCTAssertGreaterThan(consecutiveScore, scatteredScore)
    }

    func testMidWordContiguousMatchIsAllowedButMidWordRestartIsNot() throws {
        var scorer = FuzzyFileScorer()
        let target = FuzzyMatchTarget(relativeParentPath: "Sources", fileName: "SearchIndex.swift")

        // クエリ全体が1本の連続一致なら単語の途中でも拾う（substring相当）
        let midWordQuery = try XCTUnwrap(FuzzyQuery(rawQuery: "earch"))
        let midWordMatch = try XCTUnwrap(scorer.scoreWithPositions(midWordQuery, in: target))
        XCTAssertEqual(midWordMatch.positions, [9, 10, 11, 12, 13])

        // 複数セグメントに分かれる場合、単語途中からの再開は不可
        // （"search" は境界頭だが "ndex" がIndexの途中から始まる）
        let midRestartQuery = try XCTUnwrap(FuzzyQuery(rawQuery: "searchndex"))
        XCTAssertNil(scorer.score(midRestartQuery, in: target))

        // 境界頭から始まるセグメント同士なら複数セグメントでもマッチする
        let boundaryQuery = try XCTUnwrap(FuzzyQuery(rawQuery: "si"))
        let boundaryMatch = try XCTUnwrap(scorer.scoreWithPositions(boundaryQuery, in: target))
        XCTAssertEqual(boundaryMatch.positions, [8, 14])
    }

    func testUppercaseRunTreatsLastLetterAsWordStart() throws {
        var scorer = FuzzyFileScorer()

        // ZApp のA、JSONParser のPは大文字連続の末尾＝次の単語の頭として扱う
        let acronymTarget = FuzzyMatchTarget(relativeParentPath: "", fileName: "ZApp.swift")
        let appQuery = try XCTUnwrap(FuzzyQuery(rawQuery: "app"))
        let appMatch = try XCTUnwrap(scorer.scoreWithPositions(appQuery, in: acronymTarget))
        XCTAssertEqual(appMatch.positions, [1, 2, 3])

        let parserTarget = FuzzyMatchTarget(relativeParentPath: "", fileName: "JSONParser.swift")
        let parserQuery = try XCTUnwrap(FuzzyQuery(rawQuery: "parser"))
        let parserMatch = try XCTUnwrap(scorer.scoreWithPositions(parserQuery, in: parserTarget))
        XCTAssertEqual(parserMatch.positions, [4, 5, 6, 7, 8, 9])
    }

    func testSeparatorAndCJKAreExemptFromBoundaryRule() throws {
        var scorer = FuzzyFileScorer()

        // 区切り文字自身は任意位置でセグメントを開始できる（拡張子検索）
        let extensionTarget = FuzzyMatchTarget(relativeParentPath: "", fileName: "App.swift")
        let extensionQuery = try XCTUnwrap(FuzzyQuery(rawQuery: ".swift"))
        let extensionMatch = try XCTUnwrap(scorer.scoreWithPositions(extensionQuery, in: extensionTarget))
        XCTAssertEqual(extensionMatch.positions, [3, 4, 5, 6, 7, 8])

        // 単語境界が存在しないCJKは途中からでもマッチできる
        let japaneseTarget = FuzzyMatchTarget(relativeParentPath: "", fileName: "設定ファイル.md")
        let midQuery = try XCTUnwrap(FuzzyQuery(rawQuery: "ファイル"))
        let midMatch = try XCTUnwrap(scorer.scoreWithPositions(midQuery, in: japaneseTarget))
        XCTAssertEqual(midMatch.positions, [2, 3, 4, 5])
    }

    func testFileNameStartOutranksCamelAndPathOnlyMatches() throws {
        var scorer = FuzzyFileScorer()
        let query = try XCTUnwrap(FuzzyQuery(rawQuery: "app"))
        let fileNameStartTarget = FuzzyMatchTarget(relativeParentPath: "Sources", fileName: "App.swift")
        let camelTarget = FuzzyMatchTarget(relativeParentPath: "Sources", fileName: "MyApp.swift")
        let pathOnlyTarget = FuzzyMatchTarget(relativeParentPath: "App", fileName: "Notes.swift")

        let fileNameStartScore = try XCTUnwrap(scorer.score(query, in: fileNameStartTarget))
        let camelScore = try XCTUnwrap(scorer.score(query, in: camelTarget))
        let pathOnlyScore = try XCTUnwrap(scorer.score(query, in: pathOnlyTarget))

        XCTAssertGreaterThan(fileNameStartScore, camelScore)
        XCTAssertGreaterThan(camelScore, pathOnlyScore)
    }

    func testCamelCaseSubsequencePicksWordBoundaryPositions() throws {
        var scorer = FuzzyFileScorer()
        let target = FuzzyMatchTarget(relativeParentPath: "Ruri/Models", fileName: "ProjectFileSearchIndex.swift")
        let query = try XCTUnwrap(FuzzyQuery(rawQuery: "pfsi"))

        let match = try XCTUnwrap(scorer.scoreWithPositions(query, in: target))

        // fileNameStart(12) + [P, F, S, I] の camel 境界
        XCTAssertEqual(match.positions, [12, 19, 23, 29])
    }

    func testMatchIsCaseInsensitive() throws {
        var scorer = FuzzyFileScorer()
        let target = FuzzyMatchTarget(relativeParentPath: "", fileName: "app.swift")
        let lowercaseQuery = try XCTUnwrap(FuzzyQuery(rawQuery: "app"))
        let uppercaseQuery = try XCTUnwrap(FuzzyQuery(rawQuery: "APP"))

        XCTAssertEqual(scorer.score(lowercaseQuery, in: target), scorer.score(uppercaseQuery, in: target))
    }

    func testJapaneseFileNameOffsetsAlignWithDisplayCharacters() throws {
        var scorer = FuzzyFileScorer()
        let fileName = "設定ファイル.md"
        let target = FuzzyMatchTarget(relativeParentPath: "", fileName: fileName)
        let query = try XCTUnwrap(FuzzyQuery(rawQuery: "設定"))

        let match = try XCTUnwrap(scorer.scoreWithPositions(query, in: target))

        XCTAssertEqual(match.positions, [0, 1])
        XCTAssertTrue(match.positions.allSatisfy { $0 < fileName.count })
    }

    func testCaseFoldingNeverShiftsOffsets() throws {
        var scorer = FuzzyFileScorer()

        // İはlowercased()でも1 Character（i + 結合ドット）なので先頭スカラーのiでマッチし、
        // キーは常に表示Characterと1:1でオフセットはずれない
        let turkishFileName = "İstanbul.swift"
        let turkishTarget = FuzzyMatchTarget(relativeParentPath: "", fileName: turkishFileName)
        XCTAssertEqual(turkishTarget.keys.count, turkishFileName.count)

        let asciiQuery = try XCTUnwrap(FuzzyQuery(rawQuery: "i"))
        let asciiMatch = try XCTUnwrap(scorer.scoreWithPositions(asciiQuery, in: turkishTarget))
        XCTAssertEqual(asciiMatch.positions, [0])

        // ßはlowercased()で不変なのでß自身のキーになり、ssとは同一視しない
        let eszettFileName = "straße.swift"
        let eszettTarget = FuzzyMatchTarget(relativeParentPath: "", fileName: eszettFileName)
        XCTAssertEqual(eszettTarget.keys.count, eszettFileName.count)

        let eszettQuery = try XCTUnwrap(FuzzyQuery(rawQuery: "straß"))
        let eszettMatch = try XCTUnwrap(scorer.scoreWithPositions(eszettQuery, in: eszettTarget))
        XCTAssertEqual(eszettMatch.positions, [0, 1, 2, 3, 4])

        // "ss" はß(4)を同一視せず、s(0)と.swiftのs(7)を選ぶ
        let doubleSQuery = try XCTUnwrap(FuzzyQuery(rawQuery: "ss"))
        let doubleSMatch = try XCTUnwrap(scorer.scoreWithPositions(doubleSQuery, in: eszettTarget))
        XCTAssertEqual(doubleSMatch.positions, [0, 7])
    }

    func testGapPenaltyPrefersCloserMatch() throws {
        var scorer = FuzzyFileScorer()
        let query = try XCTUnwrap(FuzzyQuery(rawQuery: "ab"))
        let closeTarget = FuzzyMatchTarget(relativeParentPath: "", fileName: "a_b.swift")
        let farTarget = FuzzyMatchTarget(relativeParentPath: "", fileName: "a____b.swift")

        let closeScore = try XCTUnwrap(scorer.score(query, in: closeTarget))
        let farScore = try XCTUnwrap(scorer.score(query, in: farTarget))

        XCTAssertGreaterThan(closeScore, farScore)
    }

    func testLongQueryFallsBackToGreedyWithoutCrash() throws {
        var scorer = FuzzyFileScorer()
        let repeated = String(repeating: "ab", count: 40)
        let target = FuzzyMatchTarget(relativeParentPath: "", fileName: "\(repeated).swift")
        let rawQuery = String(repeating: "ab", count: 35)
        XCTAssertGreaterThan(rawQuery.count, FuzzyFileScorer.maxQueryLength)

        let query = try XCTUnwrap(FuzzyQuery(rawQuery: rawQuery))
        let match = try XCTUnwrap(scorer.scoreWithPositions(query, in: target))

        XCTAssertEqual(match.positions.count, rawQuery.count)
        XCTAssertEqual(match.positions, match.positions.sorted())
        XCTAssertEqual(scorer.score(query, in: target), match.score)
    }
}
