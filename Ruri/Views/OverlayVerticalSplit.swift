//
//  OverlayVerticalSplit.swift
//  ruri
//

import AppKit
import SwiftUI

struct OverlayVerticalSplit<Top: View, Bottom: View>: View {
    @Binding var topFraction: Double
    @ViewBuilder let top: () -> Top
    @ViewBuilder let bottom: () -> Bottom

    @State private var dragStartFraction: Double?

    private static var fractionRange: ClosedRange<Double> { 0.25...0.75 }
    private static var dividerHitAreaHeight: CGFloat { 9 }

    var body: some View {
        GeometryReader { geometry in
            let totalHeight = geometry.size.height
            let contentHeight = max(0, totalHeight - Self.dividerHitAreaHeight)

            VStack(spacing: 0) {
                top()
                    .frame(height: contentHeight * Self.clamp(topFraction))

                divider(totalHeight: totalHeight)

                bottom()
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private func divider(totalHeight: CGFloat) -> some View {
        ZStack {
            Divider()
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.dividerHitAreaHeight)
        .contentShape(Rectangle())
        .onHover { isHovering in
            if isHovering {
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let startFraction = dragStartFraction ?? Self.clamp(topFraction)
                    dragStartFraction = startFraction

                    let contentHeight = max(1, totalHeight - Self.dividerHitAreaHeight)
                    topFraction = Self.clamp(startFraction + value.translation.height / contentHeight)
                }
                .onEnded { _ in
                    dragStartFraction = nil
                }
        )
    }

    private static func clamp(_ fraction: Double) -> Double {
        min(max(fraction, fractionRange.lowerBound), fractionRange.upperBound)
    }
}
