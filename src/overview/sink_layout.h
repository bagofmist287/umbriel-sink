#pragma once

#include "config/config.h"

#include <cstddef>
#include <span>
#include <vector>

namespace umbriel {

  // Double precision keeps the shared centre intact until scene coordinates are rounded.
  struct OverviewBox {
    double x = 0.0;
    double y = 0.0;
    double width = 0.0;
    double height = 0.0;
  };

  struct OverviewOverhang {
    double top = 0.0;
    double bottom = 0.0;
    double left = 0.0;
    double right = 0.0;
  };

  struct OverviewProgressRange {
    double minimum = 0.0;
    double maximum = 1.0;
  };

  [[nodiscard]] double overviewSinkExtent(const Config::Overview::Sink& settings, size_t visibleDepth, size_t count);
  [[nodiscard]] double overviewSinkBudget(const Config::Overview::Sink& settings, size_t visibleDepth);
  [[nodiscard]] double overviewSinkOffset(const Config::Overview::Sink& settings, size_t visibleDepth, size_t depth);
  // Width/height are already projected, without desktop depth scale. Sink is top-aligned and horizontally centred.
  [[nodiscard]] OverviewBox overviewSinkBox(
      const OverviewBox& preview, double width, double height, const Config::Overview::Sink& settings,
      size_t visibleDepth, size_t count, size_t depth
  );
  // The caller intersects this with actual occlusion and the output clip. Deep tail decorations have no hit area.
  [[nodiscard]] double overviewSinkEntranceHeight(
      const Config::Overview::Sink& settings, size_t visibleDepth, size_t depth, double projectedHeight
  );
  [[nodiscard]] OverviewOverhang
  overviewOverhang(const OverviewBox& preview, std::span<const OverviewBox> boxes, double chromePadding = 0.0);
  // Conservative bounds over a complete unit step from rest, without sampling at guessed frame intervals.
  // Arbitrary spring release velocity requires springDisplacementBound at the owning animation layer instead.
  [[nodiscard]] OverviewProgressRange overviewCurveRange(const AnimationCurve& curve);
  [[nodiscard]] OverviewOverhang overviewSinkAnimationBudget(
      const Config::Overview::Sink& settings, size_t visibleDepth, OverviewSinkMode mode,
      const OverviewProgressRange& progress
  );
  // Encloses a geometry tween even when its curve overshoots; supports mid-flight retargeting from its actual box.
  [[nodiscard]] OverviewBox
  overviewTweenBounds(const OverviewBox& from, const OverviewBox& to, const OverviewProgressRange& progress);

  // Immutable per-epoch axis offsets. Drawing, navigation and insertion hints share the same conversion.
  // Fractional index coordinates (including rubber-band overscroll) are interpolated/extrapolated on this strip.
  class OverviewStripLayout {
  public:
    OverviewStripLayout(
        double previewExtent, double defaultGap, WorkspaceAxis axis, std::span<const OverviewOverhang> reserved
    );
    [[nodiscard]] double position(double index) const;
    [[nodiscard]] double indexAt(double position) const;
    [[nodiscard]] size_t size() const { return m_origins.size(); }

  private:
    [[nodiscard]] double firstStep() const;
    [[nodiscard]] double lastStep() const;
    std::vector<double> m_origins;
    double m_fallbackStep;
  };

} // namespace umbriel
