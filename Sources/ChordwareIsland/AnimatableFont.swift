import SwiftUI

/// A font size that interpolates.
///
/// `.font(.system(size:))` snaps between values: SwiftUI treats the font as an
/// attribute rather than something with a magnitude. Driving the size through
/// `Animatable` re-invokes the modifier every frame, so text can grow and
/// shrink with the window instead of jumping at the start of the animation.
struct AnimatableFont: ViewModifier, Animatable {
    var size: CGFloat
    var weight: Font.Weight = .semibold
    var design: Font.Design = .rounded

    var animatableData: CGFloat {
        get { size }
        set { size = newValue }
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    func animatableFont(size: CGFloat,
                        weight: Font.Weight = .semibold,
                        design: Font.Design = .rounded) -> some View {
        modifier(AnimatableFont(size: size, weight: weight, design: design))
    }
}
