#include "check.h"
#include "overview/sink_layout.h"

#include <array>
#include <cmath>
#include <limits>

using namespace umbriel;

namespace {
  bool near(double actual, double expected) { return std::abs(actual - expected) < 1e-8; }
  bool contains(const OverviewBox& bounds, const OverviewBox& box) {
    return box.x >= bounds.x - 1e-8
        && box.y >= bounds.y - 1e-8
        && box.x + box.width <= bounds.x + bounds.width + 1e-8
        && box.y + box.height <= bounds.y + bounds.height + 1e-8;
  }
} // namespace

UMBRIEL_TEST(fullEntrancesAndLongTailHaveABoundedExtent) {
  const Config::Overview::Sink settings;
  CHECK_EQ(overviewSinkExtent(settings, 2, 0), 0.0);
  CHECK_EQ(overviewSinkExtent(settings, 2, 1), 24.0);
  CHECK_EQ(overviewSinkExtent(settings, 2, 2), 48.0);
  CHECK_EQ(overviewSinkExtent(settings, 2, 3), 54.0);
  CHECK_EQ(overviewSinkExtent(settings, 2, 4), 57.0);
  CHECK_EQ(overviewSinkBudget(settings, 2), 60.0);
  CHECK_EQ(overviewSinkExtent(settings, 2, std::numeric_limits<size_t>::max()), 60.0);
  CHECK_EQ(overviewSinkOffset(settings, 2, std::numeric_limits<size_t>::max()), 60.0);
  CHECK_EQ(overviewSinkEntranceHeight(settings, 2, 0, 300), 24.0);
  CHECK_EQ(overviewSinkEntranceHeight(settings, 2, 1, 9), 9.0);
  CHECK_EQ(overviewSinkEntranceHeight(settings, 2, 2, 300), 0.0);
  for (const double decay : {0.000001, 0.5, 0.999999}) {
    for (const size_t depth : {1U, 2U, 4U}) {
      const Config::Overview::Sink large{.exposureHeight = 256, .tailHeight = 256, .tailDecay = decay};
      double previous = 0.0;
      for (size_t count = 0; count < 500; ++count) {
        const double value = overviewSinkExtent(large, depth, count);
        CHECK(value >= previous);
        CHECK(value <= overviewSinkBudget(large, depth));
        previous = value;
      }
    }
  }
  CHECK_EQ(overviewSinkExtent({.tailHeight = 0}, 4, 100), 96.0);
}

UMBRIEL_TEST(unequalWidthsShareThePreviewCentreAndOnlyVerticalDepthOffsets) {
  const Config::Overview::Sink settings;
  const OverviewBox preview{.x = -641.25, .y = 180.5, .width = 640.5, .height = 360.25};
  for (const double width : {99.5, 200.25, 640.5, 800.0}) {
    for (size_t depth = 0; depth < 4; ++depth) {
      const auto box = overviewSinkBox(preview, width, 240.0, settings, 2, 4, depth);
      CHECK(near(box.x + box.width / 2, preview.x + preview.width / 2));
      CHECK(near(box.y, preview.y + 28.5 - overviewSinkOffset(settings, 2, depth)));
      CHECK_EQ(box.height, 240.0);
    }
  }
}

UMBRIEL_TEST(sharedAnchorBalancesFullHeightForegroundAndSinkCombination) {
  const Config::Overview::Sink settings;
  const OverviewBox preview{.x = 320, .y = 180, .width = 640, .height = 360};
  const auto sunk = overviewSinkBox(preview, 320, 360, settings, 2, 2, 1);
  const OverviewBox foreground{.x = 320, .y = 204, .width = 640, .height = 360};
  const std::array boxes{sunk, foreground};
  const auto border = overviewOverhang(preview, boxes);
  CHECK_EQ(border.top, 24.0);
  CHECK_EQ(border.bottom, 24.0);
  CHECK_EQ(border.left, 0.0);
  const auto decorated = overviewOverhang(preview, boxes, 3.5);
  CHECK_EQ(decorated.top, 27.5);
  CHECK_EQ(decorated.bottom, 27.5);
  CHECK_EQ(decorated.right, 3.5);
  CHECK_EQ(overviewOverhang(preview, {}).top, 0.0);
}

UMBRIEL_TEST(curveEnvelopesCoverOvershootWithoutDependingOnFrameCadence) {
  for (uint8_t id = 0; id <= static_cast<uint8_t>(Easing::Spring); ++id) {
    const AnimationCurve curve{.easing = static_cast<Easing>(id)};
    const auto bound = overviewCurveRange(curve);
    for (int i = 0; i <= 500; ++i) {
      const double value = evaluateCurve(curve, static_cast<double>(i) / 500);
      CHECK(value >= bound.minimum - 1e-8);
      CHECK(value <= bound.maximum + 1e-8);
    }
  }
  const AnimationCurve custom{.easing = Easing::CustomBezier, .bezier = {.x1 = 0.2, .y1 = -8, .x2 = 0.8, .y2 = 15}};
  CHECK_EQ(overviewCurveRange(custom).minimum, -8.0);
  CHECK_EQ(overviewCurveRange(custom).maximum, 15.0);
  const AnimationCurve critical{.easing = Easing::Spring, .spring = {.damping = 1.0}};
  CHECK_EQ(overviewCurveRange(critical).maximum, 1.0);
}

UMBRIEL_TEST(configurationCapacityCoversEmptyToFullAndSharedProgress) {
  const Config::Overview::Sink settings;
  const OverviewProgressRange range{.minimum = -0.2, .maximum = 1.5};
  for (const auto type : {OverviewSinkMode::Performance, OverviewSinkMode::Balanced, OverviewSinkMode::Smooth}) {
    const auto reserved = overviewSinkAnimationBudget(settings, 2, type, range);
    for (size_t count = 1; count <= 200; ++count) {
      const double shift = overviewSinkExtent(settings, 2, count) / 2;
      for (size_t depth = 0; depth < count; ++depth) {
        const double offset = overviewSinkOffset(settings, 2, depth);
        for (const double foreground : {range.minimum, 0.0, 1.0, range.maximum}) {
          for (const double layer : {range.minimum, 0.0, 1.0, range.maximum}) {
            if (type != OverviewSinkMode::Performance && foreground != layer) {
              continue;
            }
            const double top =
                type == OverviewSinkMode::Performance ? shift - offset : shift * foreground - offset * layer;
            CHECK(-top <= reserved.top + 1e-8);
            CHECK(top <= reserved.bottom + 1e-8);
          }
        }
      }
    }
  }
}

UMBRIEL_TEST(nonUniformStripNavigationInvertsTheDrawingCoordinatesOnBothAxes) {
  const std::array reserved{
      OverviewOverhang{.top = 10, .bottom = 20, .left = 3, .right = 4},
      OverviewOverhang{.top = 30, .bottom = 40, .left = 5, .right = 6},
      OverviewOverhang{.top = 50, .bottom = 60, .left = 7, .right = 8},
  };
  const OverviewStripLayout vertical(360.5, 40.25, WorkspaceAxis::Vertical, reserved);
  CHECK_EQ(vertical.position(1), 450.75);
  CHECK_EQ(vertical.position(2), 941.5);
  const OverviewStripLayout horizontal(640.5, 40.25, WorkspaceAxis::Horizontal, reserved);
  CHECK_EQ(horizontal.position(1), 689.75);
  CHECK_EQ(horizontal.position(2), 1383.5);
  for (const auto* layout : {&vertical, &horizontal}) {
    for (int step = -20; step <= 40; ++step) {
      const double index = static_cast<double>(step) / 10;
      CHECK(near(layout->indexAt(layout->position(index)), index));
    }
  }
  const OverviewStripLayout empty(360, 40, WorkspaceAxis::Vertical, {});
  CHECK_EQ(empty.position(99), 0.0);
  const OverviewStripLayout single(360, 40, WorkspaceAxis::Vertical, std::span(reserved).first(1));
  CHECK_EQ(single.position(-0.5), -200.0);
  CHECK_EQ(single.indexAt(200), 0.5);
}

UMBRIEL_TEST(retargetedGeometryBoundsIncludeAllOvershootingEdges) {
  const OverviewBox from{.x = -100, .y = 230, .width = 200, .height = 150};
  const OverviewBox to{.x = 40, .y = 180, .width = 90, .height = 300};
  const OverviewProgressRange progress{.minimum = -0.25, .maximum = 1.5};
  const auto bounds = overviewTweenBounds(from, to, progress);
  for (int i = 0; i <= 100; ++i) {
    const double p = std::lerp(progress.minimum, progress.maximum, static_cast<double>(i) / 100);
    CHECK(contains(
        bounds,
        {
            .x = std::lerp(from.x, to.x, p),
            .y = std::lerp(from.y, to.y, p),
            .width = std::lerp(from.width, to.width, p),
            .height = std::lerp(from.height, to.height, p),
        }
    ));
  }
}

int main() { return RUN_TESTS(); }
