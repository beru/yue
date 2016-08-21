// Copyright 2016 Cheng Zhao. All rights reserved.
// Use of this source code is governed by the license that can be found in the
// LICENSE file.

#include "nativeui/win/screen.h"

#include <windows.h>
#include <shellscalingapi.h>

#include "base/win/scoped_hdc.h"
#include "base/win/win_util.h"

namespace nu {

namespace {

const float kDefaultDPI = 96.f;

gfx::Size GetDPI() {
  static int dpi_x = 0;
  static int dpi_y = 0;
  static bool should_initialize = true;

  if (should_initialize) {
    should_initialize = false;
    base::win::ScopedGetDC screen_dc(NULL);
    // This value is safe to cache for the life time of the app since the
    // user must logout to change the DPI setting. This value also applies
    // to all screens.
    dpi_x = GetDeviceCaps(screen_dc, LOGPIXELSX);
    dpi_y = GetDeviceCaps(screen_dc, LOGPIXELSY);
  }
  return gfx::Size(dpi_x, dpi_y);
}

float GetScalingFactorFromDPI(int dpi) {
  return static_cast<float>(dpi) / kDefaultDPI;
}

float GetDPIScale() {
  return GetScalingFactorFromDPI(GetDPI().width());
}

// Returns |hwnd|'s scale factor.
float GetScaleFactorForHWND(HWND hwnd) {
  HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);

  DCHECK(monitor);
  if (base::win::IsProcessPerMonitorDpiAware()) {
    static auto get_dpi_for_monitor_func = []() {
      using GetDpiForMonitorPtr = decltype(::GetDpiForMonitor)*;
      HMODULE shcore_dll = ::LoadLibrary(L"shcore.dll");
      if (shcore_dll) {
        return reinterpret_cast<GetDpiForMonitorPtr>(
                   ::GetProcAddress(shcore_dll, "GetDpiForMonitor"));
      }
      return static_cast<GetDpiForMonitorPtr>(nullptr);
    }();

    UINT dpi_x;
    UINT dpi_y;
    if (get_dpi_for_monitor_func &&
        SUCCEEDED(get_dpi_for_monitor_func(monitor, MDT_EFFECTIVE_DPI,
                                           &dpi_x, &dpi_y))) {
      DCHECK_EQ(dpi_x, dpi_y);
      return GetScalingFactorFromDPI(dpi_x);
    }
  }
  return GetDPIScale();
}

}  // namespace

gfx::Rect ScreenToDIPRect(HWND hwnd, const gfx::Rect& pixel_bounds) {
  float scale_factor = GetScaleFactorForHWND(hwnd);
  gfx::Rect dip_rect = ScaleToEnclosingRect(pixel_bounds, 1.0f / scale_factor);
  return dip_rect;
}

gfx::Rect DIPToScreenRect(HWND hwnd, const gfx::Rect& dip_bounds) {
  float scale_factor = GetScaleFactorForHWND(hwnd);
  gfx::Rect screen_rect = ScaleToEnclosingRect(dip_bounds, scale_factor);
  return screen_rect;
}

}  // namespace nu
