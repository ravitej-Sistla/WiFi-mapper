import GoogleMobileAds
import SwiftUI
import UIKit

/// A Google native ad laid out like the app's other cards. Google renders and tracks
/// clicks through `NativeAdView`, so the layout is UIKit inside a SwiftUI card.
struct NativeAdCard: UIViewRepresentable {
    let nativeAd: NativeAd

    func makeUIView(context: Context) -> CardAdView {
        CardAdView()
    }

    func updateUIView(_ view: CardAdView, context: Context) {
        view.show(nativeAd)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: CardAdView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let size = uiView.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                                  withHorizontalFittingPriority: .required,
                                                  verticalFittingPriority: .fittingSizeLevel)
        return CGSize(width: width, height: size.height)
    }
}

final class CardAdView: NativeAdView {
    private let icon = UIImageView()
    private let headline = UILabel()
    private let advertiser = UILabel()
    private let badge = PaddedLabel()
    private let media = MediaView()
    private let body = UILabel()
    private let action = UIButton(type: .system)
    private var mediaHeight: NSLayoutConstraint?
    private static let maxMediaHeight: CGFloat = 200
    private var content = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        icon.contentMode = .scaleAspectFill
        icon.clipsToBounds = true
        icon.layer.cornerRadius = 10
        icon.layer.cornerCurve = .continuous
        icon.backgroundColor = .secondarySystemFill
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 40),
            icon.heightAnchor.constraint(equalToConstant: 40),
        ])

        headline.font = .preferredFont(forTextStyle: .headline)
        headline.adjustsFontForContentSizeCategory = true
        headline.numberOfLines = 2
        advertiser.font = .preferredFont(forTextStyle: .caption1)
        advertiser.adjustsFontForContentSizeCategory = true
        advertiser.textColor = .secondaryLabel

        badge.text = "Ad"
        badge.font = .systemFont(ofSize: 11, weight: .bold)
        badge.textColor = UIColor(Brand.blue)
        badge.backgroundColor = UIColor(Brand.blue).withAlphaComponent(0.14)
        badge.layer.cornerRadius = 8
        badge.clipsToBounds = true
        badge.setContentHuggingPriority(.required, for: .horizontal)

        media.contentMode = .scaleAspectFit
        media.clipsToBounds = true
        media.heightAnchor.constraint(lessThanOrEqualToConstant: Self.maxMediaHeight).isActive = true
        media.layer.cornerRadius = 12
        media.layer.cornerCurve = .continuous

        body.font = .preferredFont(forTextStyle: .subheadline)
        body.adjustsFontForContentSizeCategory = true
        body.textColor = .secondaryLabel
        body.numberOfLines = 2

        var buttonConfig = UIButton.Configuration.filled()
        buttonConfig.baseBackgroundColor = UIColor(Brand.blue)
        buttonConfig.baseForegroundColor = .white
        buttonConfig.cornerStyle = .large
        buttonConfig.buttonSize = .large
        action.configuration = buttonConfig
        // The SDK handles taps on the ad; the button must not swallow them.
        action.isUserInteractionEnabled = false

        let titles = UIStackView(arrangedSubviews: [headline, advertiser])
        titles.axis = .vertical
        titles.spacing = 2
        let header = UIStackView(arrangedSubviews: [icon, titles, badge])
        header.alignment = .center
        header.spacing = 12

        let stack = content
        [header, media, body, action].forEach(stack.addArrangedSubview)
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            // 1 pt of slack: the SDK rejects asset views that overflow by even a rounding error.
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ])

        headlineView = headline
        mediaView = media
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Waiting for layout: the SDK checks that every registered asset view lies inside this view.
    private var pendingAd: NativeAd?

    func show(_ ad: NativeAd) {
        guard nativeAd !== ad, pendingAd !== ad else { return }
        headline.text = ad.headline
        advertiser.text = ad.advertiser
        advertiser.isHidden = ad.advertiser == nil
        icon.image = ad.icon?.image
        icon.isHidden = ad.icon == nil
        body.text = ad.body
        body.isHidden = ad.body == nil
        action.configuration?.title = ad.callToAction
        action.isHidden = ad.callToAction == nil

        // Register only the assets this ad has; hidden views have no frame inside the ad view.
        advertiserView = ad.advertiser == nil ? nil : advertiser
        iconView = ad.icon == nil ? nil : icon
        bodyView = ad.body == nil ? nil : body
        callToActionView = ad.callToAction == nil ? nil : action

        media.mediaContent = ad.mediaContent
        mediaHeight?.isActive = false
        let ratio = ad.mediaContent.aspectRatio > 0 ? ad.mediaContent.aspectRatio : 16 / 9
        mediaHeight = media.heightAnchor.constraint(equalTo: media.widthAnchor, multiplier: 1 / ratio)
        mediaHeight?.priority = .defaultHigh
        mediaHeight?.isActive = true

        pendingAd = ad
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Assigning the ad registers the asset views, so do it once they all have real frames:
        // nested stack views finish laying out after this pass.
        guard pendingAd != nil, bounds.width > 0, bounds.height > 0 else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let ad = self.pendingAd else { return }
            self.pendingAd = nil
            self.layoutIfNeeded()
            self.nativeAd = ad
        }
    }
}

final class PaddedLabel: UILabel {
    var insets = UIEdgeInsets(top: 3, left: 7, bottom: 3, right: 7)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}
