// Copyright 2017 Cheng Zhao. All rights reserved.
// Use of this source code is governed by the license that can be found in the
// LICENSE file.

#include "nativeui/mac/nu_private.h"

#include <objc/objc-runtime.h>

#include "base/mac/mac_util.h"
#include "nativeui/mac/mouse_capture.h"
#include "nativeui/mac/view_mac.h"

namespace nu {

namespace {

bool NUInjected(NSView* self, SEL _cmd) {
  return true;
}

View* GetShell(NSView* self, SEL _cmd) {
  return [self nuPrivate]->shell;
}

BOOL AcceptsFirstResponder(NSView* self, SEL _cmd) {
  return [self nuPrivate]->focusable;
}

BOOL MouseDownCanMoveWindow(NSView* self, SEL _cmd) {
  return [self nuPrivate]->draggable;
}

void SetFrameSize(NSView* self, SEL _cmd, NSSize size) {
  if ([self nuPrivate]->is_content_view && [self superview])
    size = [[self superview] bounds].size;

  auto super_impl = reinterpret_cast<decltype(&SetFrameSize)>(
      [[self superclass] instanceMethodForSelector:_cmd]);
  super_impl(self, _cmd, size);
}

void ViewDidMoveToSuperview(NSView* self, SEL _cmd) {
  if (![self nuPrivate]->is_content_view) {
    auto super_impl = reinterpret_cast<decltype(&ViewDidMoveToSuperview)>(
        [[self superclass] instanceMethodForSelector:_cmd]);
    super_impl(self, _cmd);
    return;
  }

  [self setFrame:[[self superview] bounds]];
}

void EnableTracking(NSView* self, SEL _cmd) {
  NUPrivate* priv = [self nuPrivate];
  NSTrackingAreaOptions trackingOptions = NSTrackingMouseEnteredAndExited |
                                          NSTrackingMouseMoved |
                                          NSTrackingActiveAlways |
                                          NSTrackingInVisibleRect;
  priv->tracking_area.reset([[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                         options:trackingOptions
                                                           owner:self
                                                        userInfo:nil]);
  [self addTrackingArea:priv->tracking_area.get()];
}

void DisableTracking(NSView* self, SEL _cmd) {
  NUPrivate* priv = [self nuPrivate];
  if (priv->tracking_area) {
    [self removeTrackingArea:priv->tracking_area.get()];
    priv->tracking_area.reset();
  }
}

void UpdateTrackingAreas(NSView* self, SEL _cmd) {
  // [super updateTrackingAreas]
  auto super_impl = reinterpret_cast<void (*)(NSView*, SEL)>(
      [[self superclass] instanceMethodForSelector:_cmd]);
  super_impl(self, _cmd);

  [self disableTracking];
  [self enableTracking];
}

}  // namespace

NUPrivate::NUPrivate() {
}

NUPrivate::~NUPrivate() {
}

bool IsNUView(id view) {
  return [view respondsToSelector:@selector(nuPrivate)];
}

bool ViewMethodsInstalled(Class cl) {
  return class_getClassMethod(cl, @selector(nuInjected)) != nullptr;
}

void AddViewMethods(Class cl) {
  class_addMethod(cl, @selector(nuInjected), (IMP)NUInjected, "B@:");
  class_addMethod(cl, @selector(shell), (IMP)GetShell, "^v@:");
  class_addMethod(cl, @selector(acceptsFirstResponder),
                  (IMP)AcceptsFirstResponder, "B@:");
  class_addMethod(cl, @selector(mouseDownCanMoveWindow),
                  (IMP)MouseDownCanMoveWindow, "B@:");
  class_addMethod(cl, @selector(setFrameSize:),
                  (IMP)SetFrameSize, "v@:{_NSSize=ff}");
  class_addMethod(cl, @selector(viewDidMoveToSuperview),
                  (IMP)ViewDidMoveToSuperview, "v@:");
  class_addMethod(cl, @selector(enableTracking), (IMP)EnableTracking, "v@:");
  class_addMethod(cl, @selector(disableTracking), (IMP)DisableTracking, "v@:");

  // NSTrackingInVisibleRect doesn't work correctly with Lion's window resizing,
  // http://crbug.com/176725 / http://openradar.appspot.com/radar?id=2773401 .
  // Work around it by reinstalling the tracking area after window resize.
  // This AppKit bug is fixed on Yosemite, so we only apply this workaround on
  // 10.9.
  if (base::mac::IsOS10_9())
    class_addMethod(cl, @selector(updateTrackingAreas),
                    (IMP)UpdateTrackingAreas, "v@:");
}

}  // namespace nu