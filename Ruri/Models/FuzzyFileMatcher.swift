//
//  FuzzyFileMatcher.swift
//  ruri
//

import Foundation

// クイックオープン用のファジーマッチ。fzf/VSCode系の「サブシーケンス判定で絞ってからDPでスコアリング」
// 方式で、マッチ位置はハイライト表示に使うため表示Character単位のオフセットで返す。
// マッチは2形態を許す:
// 1. クエリ全体が1本の連続一致（substring相当）— 単語の途中からでも拾う
// 2. 複数セグメントに分かれるマッチ — 各セグメントの開始は単語境界
//    （camel/kebab/snake/パス区切り直後・ファイル名先頭）に限る
// 単語構造を持たないCJK等と区切り文字自身は境界制約の対象外（任意位置でセグメント開始可能）。
// 比較キーは表示Characterごとに1つ事前計算するため、lowercased()の結果に関わらずオフセットは
// 表示文字列とずれない。小文字化でCharacter数が変わる稀な文字は原文キーで扱う（防御的分岐）。

private enum FuzzyMatchScore {
    static let match = 16
    static let bonusFileNameStart: UInt8 = 16
    static let bonusBoundary: UInt8 = 12
    static let bonusCamel: UInt8 = 10
    // 境界再開（bonusBoundary - gapStart = 9）より連続一致が常に勝つように10にする
    static let consecutive = 10
    static let fileNameRegion = 8
    static let gapStart = 3
    static let gapExtend = 1
}

struct FuzzyMatchTarget: Equatable, Sendable {
    let keys: [UInt32]
    let bonus: [UInt8]
    // マッチセグメントを開始できる位置。単語境界に加えて、単語構造を持たない文字
    // （CJK等のcasingなし文字・区切り文字自身）は任意位置で開始できる
    let canStartSegment: [Bool]
    let fileNameStartIndex: Int

    nonisolated init(relativeParentPath: String, fileName: String) {
        let relativePath = relativeParentPath.isEmpty ? fileName : "\(relativeParentPath)/\(fileName)"
        let fileNameStartIndex = relativeParentPath.isEmpty ? 0 : relativeParentPath.count + 1

        let characters = Array(relativePath)
        let classes = characters.map(Self.characterClass)

        var keys = [UInt32]()
        keys.reserveCapacity(characters.count)
        var bonus = [UInt8](repeating: 0, count: characters.count)
        var canStartSegment = [Bool](repeating: false, count: characters.count)

        for index in characters.indices {
            keys.append(Self.comparisonKey(for: characters[index]))

            let currentClass = classes[index]
            let previousClass = index == 0 ? .separator : classes[index - 1]

            let positionBonus: UInt8
            if index == fileNameStartIndex {
                positionBonus = FuzzyMatchScore.bonusFileNameStart
            } else if previousClass == .separator || previousClass == .pathSeparator {
                positionBonus = FuzzyMatchScore.bonusBoundary
            } else if currentClass == .uppercase, previousClass == .lowercase {
                positionBonus = FuzzyMatchScore.bonusCamel
            } else if currentClass == .uppercase, previousClass == .uppercase,
                      index + 1 < classes.count, classes[index + 1] == .lowercase {
                // 大文字連続の末尾（ZApp のA、JSONParser のP）は次の単語の頭として扱う
                positionBonus = FuzzyMatchScore.bonusCamel
            } else if currentClass == .digit, previousClass != .digit {
                positionBonus = FuzzyMatchScore.bonusCamel
            } else {
                positionBonus = 0
            }

            bonus[index] = positionBonus
            canStartSegment[index] = positionBonus > 0
                || currentClass == .separator
                || currentClass == .pathSeparator
                || currentClass == .other
        }

        self.keys = keys
        self.bonus = bonus
        self.canStartSegment = canStartSegment
        self.fileNameStartIndex = fileNameStartIndex
    }

    nonisolated static func comparisonKey(for character: Character) -> UInt32 {
        let lowered = String(character).lowercased()
        if lowered.count == 1, let scalar = lowered.unicodeScalars.first {
            return scalar.value
        }
        return character.unicodeScalars.first?.value ?? 0
    }

    private enum CharacterClass {
        case pathSeparator
        case separator
        case lowercase
        case uppercase
        case digit
        case other
    }

    private nonisolated static func characterClass(_ character: Character) -> CharacterClass {
        if character == "/" {
            return .pathSeparator
        }
        if character == "." || character == "_" || character == "-" || character == " " {
            return .separator
        }
        if character.isUppercase {
            return .uppercase
        }
        if character.isNumber {
            return .digit
        }
        if character.isLowercase {
            return .lowercase
        }
        return .other
    }
}

struct FuzzyQuery: Equatable, Sendable {
    let keys: [UInt32]

    nonisolated init?(rawQuery: String) {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.keys = trimmed.map { FuzzyMatchTarget.comparisonKey(for: $0) }
    }
}

// DPバッファを再利用するため可変で使う。Sendableにせず、search()呼び出し内でローカル生成する
struct FuzzyFileScorer {
    nonisolated static let maxQueryLength = 64
    nonisolated static let maxTargetLength = 512

    // DPの遷移で「未到達」を表す番人値。gap減算を重ねても実スコアと交差しない深さに置く
    private static let invalidScore = Int.min / 4
    private static let validThreshold = Int.min / 8

    private var previousRow: [Int] = []
    private var currentRow: [Int] = []
    private var matrix: [Int] = []

    nonisolated mutating func score(_ query: FuzzyQuery, in target: FuzzyMatchTarget) -> Int? {
        guard let windowStart = Self.subsequenceStart(of: query, in: target) else { return nil }

        let contiguous = Self.bestContiguousMatch(query, in: target, from: windowStart)
        guard Self.fitsInDynamicProgramming(query: query, target: target) else {
            return Self.better(contiguous, Self.greedyMatch(query, in: target))?.score
        }

        let boundaryScore = boundaryDPScore(query, in: target, windowStart: windowStart)
        return [contiguous?.score, boundaryScore].compactMap(\.self).max()
    }

    nonisolated mutating func scoreWithPositions(
        _ query: FuzzyQuery,
        in target: FuzzyMatchTarget
    ) -> (score: Int, positions: [Int])? {
        guard let windowStart = Self.subsequenceStart(of: query, in: target) else { return nil }

        let contiguous = Self.bestContiguousMatch(query, in: target, from: windowStart)
        guard Self.fitsInDynamicProgramming(query: query, target: target) else {
            return Self.better(contiguous, Self.greedyMatch(query, in: target))
        }

        return Self.better(contiguous, boundaryDPMatch(query, in: target, windowStart: windowStart))
    }

    private nonisolated mutating func boundaryDPScore(
        _ query: FuzzyQuery,
        in target: FuzzyMatchTarget,
        windowStart: Int
    ) -> Int? {
        let queryLength = query.keys.count
        let targetLength = target.keys.count
        Self.fill(&previousRow, count: targetLength)

        for column in windowStart..<targetLength
        where target.keys[column] == query.keys[0] && target.canStartSegment[column] {
            previousRow[column] = Self.baseScore(at: column, target: target)
        }

        for row in 1..<queryLength {
            Self.fill(&currentRow, count: targetLength)
            var carry = Self.invalidScore
            var rowHasMatch = false

            for column in (windowStart + row)..<targetLength {
                if column >= 2 {
                    var updated = carry > Self.validThreshold ? carry - FuzzyMatchScore.gapExtend : Self.invalidScore
                    let openedGap = previousRow[column - 2]
                    if openedGap > Self.validThreshold {
                        updated = max(updated, openedGap - FuzzyMatchScore.gapStart)
                    }
                    carry = updated
                }

                guard target.keys[column] == query.keys[row] else { continue }

                // gap越しの再開はセグメント開始可能位置に限る。直前文字からの連続は常に可
                var best = target.canStartSegment[column] ? carry : Self.invalidScore
                let consecutive = previousRow[column - 1]
                if consecutive > Self.validThreshold {
                    best = max(best, consecutive + FuzzyMatchScore.consecutive)
                }
                guard best > Self.validThreshold else { continue }

                currentRow[column] = best + Self.baseScore(at: column, target: target)
                rowHasMatch = true
            }

            guard rowHasMatch else { return nil }
            swap(&previousRow, &currentRow)
        }

        // バッファはtargetより長く再利用され得るため、有効範囲だけを見る
        var best = Self.invalidScore
        for column in 0..<targetLength {
            best = max(best, previousRow[column])
        }
        return best > Self.validThreshold ? best : nil
    }

    private nonisolated mutating func boundaryDPMatch(
        _ query: FuzzyQuery,
        in target: FuzzyMatchTarget,
        windowStart: Int
    ) -> (score: Int, positions: [Int])? {
        let queryLength = query.keys.count
        let targetLength = target.keys.count
        Self.fill(&matrix, count: queryLength * targetLength)

        for column in windowStart..<targetLength
        where target.keys[column] == query.keys[0] && target.canStartSegment[column] {
            matrix[column] = Self.baseScore(at: column, target: target)
        }

        for row in 1..<queryLength {
            let rowOffset = row * targetLength
            let previousRowOffset = rowOffset - targetLength
            var carry = Self.invalidScore
            var rowHasMatch = false

            for column in (windowStart + row)..<targetLength {
                if column >= 2 {
                    var updated = carry > Self.validThreshold ? carry - FuzzyMatchScore.gapExtend : Self.invalidScore
                    let openedGap = matrix[previousRowOffset + column - 2]
                    if openedGap > Self.validThreshold {
                        updated = max(updated, openedGap - FuzzyMatchScore.gapStart)
                    }
                    carry = updated
                }

                guard target.keys[column] == query.keys[row] else { continue }

                var best = target.canStartSegment[column] ? carry : Self.invalidScore
                let consecutive = matrix[previousRowOffset + column - 1]
                if consecutive > Self.validThreshold {
                    best = max(best, consecutive + FuzzyMatchScore.consecutive)
                }
                guard best > Self.validThreshold else { continue }

                matrix[rowOffset + column] = best + Self.baseScore(at: column, target: target)
                rowHasMatch = true
            }

            guard rowHasMatch else { return nil }
        }

        return traceback(queryLength: queryLength, targetLength: targetLength, target: target)
    }

    // 最終行の最大値から遷移を逆に辿ってマッチ位置を復元する。同点は連続一致→近い位置を優先し、
    // ハイライトが不必要に散らばらないようにする
    private nonisolated func traceback(
        queryLength: Int,
        targetLength: Int,
        target: FuzzyMatchTarget
    ) -> (score: Int, positions: [Int])? {
        let lastRowOffset = (queryLength - 1) * targetLength
        var bestColumn = -1
        var bestScore = Self.invalidScore
        for column in 0..<targetLength where matrix[lastRowOffset + column] > bestScore {
            bestScore = matrix[lastRowOffset + column]
            bestColumn = column
        }
        guard bestScore > Self.validThreshold else { return nil }

        var positions = [Int](repeating: 0, count: queryLength)
        var column = bestColumn
        positions[queryLength - 1] = column

        var row = queryLength - 1
        while row >= 1 {
            let previousRowOffset = (row - 1) * targetLength
            let predecessorScore = matrix[row * targetLength + column] - Self.baseScore(at: column, target: target)

            let consecutive = matrix[previousRowOffset + column - 1]
            if consecutive > Self.validThreshold, consecutive + FuzzyMatchScore.consecutive == predecessorScore {
                column -= 1
            } else {
                // gap遷移はセグメント開始可能位置でしか起きない（DPの遷移と対で保つ）
                var candidate = target.canStartSegment[column] ? column - 2 : -1
                while candidate >= 0 {
                    let value = matrix[previousRowOffset + candidate]
                    if value > Self.validThreshold,
                       value - FuzzyMatchScore.gapStart
                           - (column - candidate - 2) * FuzzyMatchScore.gapExtend == predecessorScore {
                        column = candidate
                        break
                    }
                    candidate -= 1
                }
            }

            positions[row - 1] = column
            row -= 1
        }

        return (bestScore, positions)
    }

    // クエリ全体が1本の連続一致になる場合は単語途中でも許す（substring検索相当）。
    // 複数候補があれば境界ボーナス込みで最高スコアの開始位置を選ぶ
    private nonisolated static func bestContiguousMatch(
        _ query: FuzzyQuery,
        in target: FuzzyMatchTarget,
        from startIndex: Int
    ) -> (score: Int, positions: [Int])? {
        let queryLength = query.keys.count
        let targetLength = target.keys.count
        guard queryLength <= targetLength else { return nil }

        var bestScore = Int.min
        var bestStart = -1

        for start in startIndex...(targetLength - queryLength) {
            var isMatch = true
            var score = 0
            for offset in 0..<queryLength {
                guard target.keys[start + offset] == query.keys[offset] else {
                    isMatch = false
                    break
                }
                score += baseScore(at: start + offset, target: target)
                if offset > 0 {
                    score += FuzzyMatchScore.consecutive
                }
            }
            if isMatch, score > bestScore {
                bestScore = score
                bestStart = start
            }
        }

        guard bestStart >= 0 else { return nil }
        return (bestScore, Array(bestStart..<(bestStart + queryLength)))
    }

    // 同点は連続一致（lhs=contiguous）を優先し、ハイライトが1本にまとまるようにする
    private nonisolated static func better(
        _ lhs: (score: Int, positions: [Int])?,
        _ rhs: (score: Int, positions: [Int])?
    ) -> (score: Int, positions: [Int])? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }
        return rhs.score > lhs.score ? rhs : lhs
    }

    private nonisolated static func baseScore(at index: Int, target: FuzzyMatchTarget) -> Int {
        var score = FuzzyMatchScore.match + Int(target.bonus[index])
        if index >= target.fileNameStartIndex {
            score += FuzzyMatchScore.fileNameRegion
        }
        return score
    }

    private nonisolated static func fitsInDynamicProgramming(query: FuzzyQuery, target: FuzzyMatchTarget) -> Bool {
        query.keys.count <= maxQueryLength && target.keys.count <= maxTargetLength
    }

    private nonisolated static func subsequenceStart(of query: FuzzyQuery, in target: FuzzyMatchTarget) -> Int? {
        guard !query.keys.isEmpty, query.keys.count <= target.keys.count else { return nil }

        var queryIndex = 0
        var firstMatchIndex = 0
        for (targetIndex, key) in target.keys.enumerated() where key == query.keys[queryIndex] {
            if queryIndex == 0 {
                firstMatchIndex = targetIndex
            }
            queryIndex += 1
            if queryIndex == query.keys.count {
                return firstMatchIndex
            }
        }
        return nil
    }

    // DP対象外の長大なquery/targetに対する安全弁。前方一致貪欲でスコアと位置を返す
    private nonisolated static func greedyMatch(
        _ query: FuzzyQuery,
        in target: FuzzyMatchTarget
    ) -> (score: Int, positions: [Int])? {
        var positions = [Int]()
        positions.reserveCapacity(query.keys.count)
        var queryIndex = 0
        var score = 0
        var lastMatchIndex = -1

        for targetIndex in 0..<target.keys.count {
            guard queryIndex < query.keys.count, target.keys[targetIndex] == query.keys[queryIndex] else { continue }
            guard targetIndex == lastMatchIndex + 1 || target.canStartSegment[targetIndex] else { continue }

            var matchScore = baseScore(at: targetIndex, target: target)
            if lastMatchIndex >= 0 {
                let gap = targetIndex - lastMatchIndex - 1
                if gap == 0 {
                    matchScore += FuzzyMatchScore.consecutive
                } else {
                    matchScore -= FuzzyMatchScore.gapStart + (gap - 1) * FuzzyMatchScore.gapExtend
                }
            }

            score += matchScore
            positions.append(targetIndex)
            lastMatchIndex = targetIndex
            queryIndex += 1
        }

        guard queryIndex == query.keys.count else { return nil }
        return (score, positions)
    }

    private nonisolated static func fill(_ buffer: inout [Int], count: Int) {
        if buffer.count < count {
            buffer = [Int](repeating: Self.invalidScore, count: count)
        } else {
            for index in 0..<count {
                buffer[index] = Self.invalidScore
            }
        }
    }
}
