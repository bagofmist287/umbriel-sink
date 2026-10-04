#include "overview/sink_layout.h"

#include <algorithm>
#include <cassert>
#include <cmath>
#include <iterator>
#include <utility>

namespace umbriel {

  namespace {
    double tailHeight(const Config::Overview::Sink& settings, size_t count) {
      // expm1 preserves the very small first tail step when q approaches one.
      return count == 0 ? 0.0
                        : -settings.tailHeight * std::expm1(static_cast<double>(count) * std::log(settings.tailDecay));
    }

    std::pair<double, double> tweenRange(double from, double to, const OverviewProgressRange& progress) {
      const double first = std::lerp(from, to, progress.minimum);
      const double last = std::lerp(from, to, progress.maximum);
      return std::minmax(first, last);
    }
  } // namespace

  double overviewSinkExtent(const Config::Overview::Sink& settings, size_t visibleDepth, size_t count) {
    assert(visibleDepth > 0);
    const size_t full = std::min(count, visibleDepth);
    return static_cast<double>(full) * settings.exposureHeight + tailHeight(settings, count - full);
  }

  double overviewSinkBudget(const Config::Overview::Sink& settings, size_t visibleDepth) {
    return static_cast<double>(visibleDepth) * settings.exposureHeight + settings.tailHeight;
  }

  double overviewSinkOffset(const Config::Overview::Sink& settings, size_t visibleDepth, size_t depth) {
    assert(visibleDepth > 0);
    if (depth < visibleDepth) {
      return static_cast<double>(depth + 1) * settings.exposureHeight;
    }
    // Avoid depth+1 overflowing at SIZE_MAX.
    return static_cast<double>(visibleDepth) * settings.exposureHeight + tailHeight(settings, depth - visibleDepth + 1);
  }

  OverviewBox overviewSinkBox(
      const OverviewBox& preview, double width, double height, const Config::Overview::Sink& settings,
      size_t visibleDepth, size_t count, size_t depth
  ) {
    assert(depth < count);
    return {
        .x = preview.x + (preview.width - width) / 2.0,
        .y = preview.y
            + overviewSinkExtent(settings, visibleDepth, count) / 2.0
            - overviewSinkOffset(settings, visibleDepth, depth),
        .width = width,
        .height = height,
    };
  }

  double overviewSinkEntranceHeight(
      const Config::Overview::Sink& settings, size_t visibleDepth, size_t depth, double projectedHeight
  ) {
    return depth < visibleDepth ? std::min(static_cast<double>(settings.exposureHeight), std::max(0.0, projectedHeight))
                                : 0.0;
  }

  OverviewOverhang
  overviewOverhang(const OverviewBox& preview, std::span<const OverviewBox> boxes, double chromePadding) {
    OverviewOverhang result;
    for (const auto& box : boxes) {
      result.top = std::max(result.top, preview.y - box.y + chromePadding);
      result.bottom = std::max(result.bottom, box.y + box.height - preview.y - preview.height + chromePadding);
      result.left = std::max(result.left, preview.x - box.x + chromePadding);
      result.right = std::max(result.right, box.x + box.width - preview.x - preview.width + chromePadding);
    }
    return result;
  }

  OverviewProgressRange overviewCurveRange(const AnimationCurve& curve) {
    switch (curve.easing) {
    case Easing::Spring:
      // Remaining mechanical energy bounds a unit step from rest by [0,2]. Non-oscillating springs are tighter.
      return {.minimum = 0.0, .maximum = curve.spring.damping >= 1.0 ? 1.0 : 2.0};
    case Easing::Snappy:
      return {.minimum = 0.0, .maximum = 1.05};
    case Easing::CustomBezier:
      // A Bezier stays in the convex hull of its control points, including for extreme custom overshoot.
      return {
          .minimum = std::min({0.0, curve.bezier.y1, curve.bezier.y2}),
          .maximum = std::max({1.0, curve.bezier.y1, curve.bezier.y2}),
      };
    case Easing::EaseInBack:
    case Easing::EaseOutBack:
    case Easing::EaseInOutBack:
    case Easing::EaseInElastic:
    case Easing::EaseOutElastic:
    case Easing::EaseInOutElastic:
      return {.minimum = -1.0, .maximum = 2.0};
    default:
      return {};
    }
  }

  OverviewOverhang overviewSinkAnimationBudget(
      const Config::Overview::Sink& settings, size_t visibleDepth, OverviewSinkMode mode,
      const OverviewProgressRange& progress
  ) {
    const double budget = overviewSinkBudget(settings, visibleDepth);
    if (mode == OverviewSinkMode::Performance) {
      return {.top = budget / 2.0, .bottom = budget / 2.0};
    }
    const double low = std::min(0.0, progress.minimum);
    const double high = std::max(1.0, progress.maximum);
    const double half = budget / 2.0 * std::max(-low, high);
    return {.top = half, .bottom = half};
  }

  OverviewBox
  overviewTweenBounds(const OverviewBox& from, const OverviewBox& to, const OverviewProgressRange& progress) {
    const double left = tweenRange(from.x, to.x, progress).first;
    const double top = tweenRange(from.y, to.y, progress).first;
    const double right = tweenRange(from.x + from.width, to.x + to.width, progress).second;
    const double bottom = tweenRange(from.y + from.height, to.y + to.height, progress).second;
    return {.x = left, .y = top, .width = right - left, .height = bottom - top};
  }

  OverviewStripLayout::OverviewStripLayout(
      double previewExtent, double defaultGap, WorkspaceAxis axis, std::span<const OverviewOverhang> reserved
  )
      : m_fallbackStep(previewExtent + defaultGap) {
    assert(previewExtent > 0.0 && defaultGap >= 0.0);
    if (reserved.empty()) {
      return;
    }
    m_origins.push_back(0.0);
    for (size_t i = 1; i < reserved.size(); ++i) {
      const double extra = axis == WorkspaceAxis::Vertical ? reserved[i - 1].bottom + reserved[i].top
                                                           : reserved[i - 1].right + reserved[i].left;
      m_origins.push_back(m_origins.back() + m_fallbackStep + extra);
    }
  }

  double OverviewStripLayout::firstStep() const {
    return m_origins.size() < 2 ? m_fallbackStep : m_origins[1] - m_origins[0];
  }

  double OverviewStripLayout::lastStep() const {
    return m_origins.size() < 2 ? m_fallbackStep : m_origins.back() - m_origins[m_origins.size() - 2];
  }

  double OverviewStripLayout::position(double index) const {
    if (m_origins.empty()) {
      return 0.0;
    }
    if (index <= 0.0) {
      return index * firstStep();
    }
    const auto last = static_cast<double>(m_origins.size() - 1);
    if (index >= last) {
      return m_origins.back() + (index - last) * lastStep();
    }
    const auto lower = static_cast<size_t>(std::floor(index));
    return std::lerp(m_origins[lower], m_origins[lower + 1], index - static_cast<double>(lower));
  }

  double OverviewStripLayout::indexAt(double position) const {
    if (m_origins.empty()) {
      return 0.0;
    }
    if (position <= 0.0) {
      return position / firstStep();
    }
    if (position >= m_origins.back()) {
      return static_cast<double>(m_origins.size() - 1) + (position - m_origins.back()) / lastStep();
    }
    const auto upper = std::ranges::upper_bound(m_origins, position);
    const auto lower = static_cast<size_t>(std::distance(m_origins.begin(), upper) - 1);
    return static_cast<double>(lower) + (position - m_origins[lower]) / (m_origins[lower + 1] - m_origins[lower]);
  }

} // namespace umbriel
