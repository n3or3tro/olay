# Fit_Text_And_Grow Button Layout Analysis

## Problem Description

From `ui.odin` lines 335-344, buttons with `.Fit_Text_And_Grow` sizing are not filling their parent container properly:

```odin
child_container(
    "@fasdflaksjd",
    {semantic_size = {{.Fixed, 200}, {.Fixed, 60}}, color = .Inactive},
    {alignment_horizontal = .Center, alignment_vertical = .Center, direction = .Horizontal},
    {.Draw},
)
text_button("hey@lllll", {color = .Primary, semantic_size = {{.Fit_Text_And_Grow, 1}, {.Fit_Text_And_Grow, 10}}})
text_button("mate@aaaaa", {color = .Tertiary, semantic_size = {{.Fit_Text_And_Grow, 1}, {.Fit_Text_And_Grow, 10}}})
text_button("baby@bbbbbbb", {color = .Primary, semantic_size = {{.Fit_Text_And_Grow, 1}, {.Fit_Text_And_Grow, 10}}})
```

Additionally, when the parent container is changed to `.Fit_Children`, the container has 0 sizing.

## Test Results

Created comprehensive test suite in `layout_fit_text_and_grow_tests.odin` covering:
- Basic Fit_Text_And_Grow in horizontal layout
- Multiple Fit_Text_And_Grow children
- Fit_Children parent with Fit_Text_And_Grow children
- Sizing order dependencies
- Different grow amounts on different axes
- Center alignment interaction
- The exact UI scenario
- Zero initial size handling

**All 10 tests pass** - confirming the test setup is correct.

## Expected vs Actual Behavior

### Expected Behavior:
1. Buttons start with their fit-text size (e.g., 35px, 40px, 45px for "hey", "mate", "baby")
2. During grow phase, buttons expand to fill available space in 200px container
3. With equal grow amounts (1.0), buttons should grow equally
4. Final sizes should total ~200px

### Current Layout Flow (from ui.odin:399-404):
```odin
sizing_calc_percent_width(root)
sizing_calc_percent_height(root)
sizing_grow_growable_height(root)
sizing_grow_growable_width(root)
recalc_fit_children_sizing(root)
position_boxes(root)
```

### Fit_Text Sizing Timing:
- Fit_Text sizing happens in `box_make`/`box_from_cache` (core.odin:310-325)
- This occurs **during box creation**, before the layout passes
- So buttons should have their fit-text size before grow phase

## Potential Issues

### Issue 1: Growth Not Happening
The `.Fit_Text_And_Grow` type should be recognized as growable in `sizing_grow_growable_width`:
```odin
if size_type == .Grow || size_type == .Fit_Text_And_Grow || size_type == .Fit_Children_And_Grow {
    // grow logic
}
```

**Confirmed**: This check exists in core.odin:921 and 940 ✓

### Issue 2: Center Alignment Interaction
The container has `alignment_horizontal = .Center`. If positioning happens before growth completes, buttons might be centered at their initial fit-text size and not re-positioned after growing.

**Layout order**: Grow happens before positioning, so this should be fine ✓

### Issue 3: Fit_Children Parent Calculates Before Children Sized
If parent is `.Fit_Children` and calculates its size before children have been fit-to-text, it would calculate as 0.

**Test result**: `test_fit_text_and_grow_sizing_order` confirms this is a problem when children start at width=0.

## Recommended Investigation Steps

1. **Add debug output** to `sizing_grow_growable_width` to verify:
   - Are Fit_Text_And_Grow boxes being added to `growable_children`?
   - What are their initial widths?
   - How much are they growing?

2. **Check text button creation** in `builder_basics.odin:35-38`:
   ```odin
   text_button :: proc(id_string: string, config: Box_Config, extra_flags := Box_Flags{}) -> Box_Signals {
       box := box_from_cache(id_string, {...}, config)
       return box_signals(box)
   }
   ```
   Does `box_from_cache` properly set Fit_Text width from the label?

3. **Verify grow algorithm** handles the "smallest equals" logic correctly (core.odin:906-911):
   The algorithm grows boxes that are currently smallest. With buttons starting at different fit-text sizes, this might cause uneven distribution.

4. **Test center alignment** - does the positioning code account for boxes that have grown?

## Key Code Locations

- Text button creation: `builder_basics.odin:35-38`
- Fit_Text sizing: `core.odin:310-325` (in box_make/box_from_cache)
- Grow width logic: `core.odin:885-931`
- Center alignment: `core.odin:1154-1170`
- Layout flow: `ui.odin:399-404`

## Next Steps

To identify the exact problem, add temporary debug output or breakpoints at:
1. `text_button` creation - check initial box width
2. `sizing_grow_growable_width` - check if buttons are being grown
3. Center alignment positioning - check if positions account for grown sizes
