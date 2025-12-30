# Debug Steps for Height Growth Issue

## Diagnostic Code to Add

Add this temporary debug output to `sizing_grow_growable_height` at line 1011 in core.odin:

```odin
case .Horizontal:
    // ADD THIS DEBUG OUTPUT:
    if box.id == "@fasdflaksjsomethingsomethingd" {
        printfln("=== CROSS-AXIS HEIGHT GROWTH DEBUG ===")
        printfln("Parent: {} | direction: {} | height: {}", box.id, box.child_layout.direction, box.height)
        printfln("Parent padding: top={}, bottom={}", box.config.padding.top, box.config.padding.bottom)
    }

    growable_amount := box.height - box_get_padding_y_tot(box^)

    // ADD THIS DEBUG OUTPUT:
    if box.id == "@fasdflaksjsomethingsomethingd" {
        printfln("Growable amount (height - padding): {}", growable_amount)
        printfln("Number of children: {}", len(box.children))
    }

    for child in box.children {
        if child.config.floating_type != .Not_Floating {
            continue
        }
        size_type := child.config.semantic_size.y.type

        // ADD THIS DEBUG OUTPUT:
        if box.id == "@fasdflaksjsomethingsomethingd" {
            printfln("  Child: {} | y size type: {} | current height: {}", child.id, size_type, child.height)
            printfln("  Child margin y: top={}, bottom={}", child.config.margin.top, child.config.margin.bottom)
        }

        if size_type == .Grow || size_type == .Fit_Text_And_Grow || size_type == .Fit_Children_And_Grow {
            old_height := child.height
            child.height += growable_amount - (child.height + box_get_margin_y_tot(child^))

            // ADD THIS DEBUG OUTPUT:
            if box.id == "@fasdflaksjsomethingsomethingd" {
                printfln("  -> Growing from {} to {}", old_height, child.height)
            }

            box_clamp_to_constraints(child)

            // ADD THIS DEBUG OUTPUT:
            if box.id == "@fasdflaksjsomethingsomethingd" {
                printfln("  -> After clamping: {}", child.height)
            }

            sizing_calc_percent_height(child)
        }
    }
```

## What to Look For

Run the program and look for the debug output. Check:

1. **Is the parent height correct?** Should be 60
2. **Is growable_amount correct?** Should be 60 (or 60 minus padding)
3. **How many children does it have?** Should be 1 (the button)
4. **What is the child's y size type?** Should be `.Fit_Text_And_Grow`
5. **What is the child's current height?** Should be ~20 (text height)
6. **What does it grow to?** Should be 60
7. **After clamping, what is it?** Should still be 60 (unless there's a max_size constraint)

## Possible Issues

### Issue 1: Button Not Actually a Child
If you see "Number of children: 0", the button isn't actually a child of the container. This would happen if the deferred close isn't working.

### Issue 2: Wrong Size Type
If the size type isn't `.Fit_Text_And_Grow`, the button won't grow. Check what you're passing in the config.

### Issue 3: Max Size Constraint
If the button grows to 60 but then gets clamped back down, there's a `max_size` constraint being applied. Check if `box_clamp_to_constraints` is changing it.

### Issue 4: Function Not Being Called
If you don't see ANY debug output, `sizing_grow_growable_height` isn't being called for this container, which means the layout flow is wrong.

### Issue 5: Parent Height Wrong
If the parent height is NOT 60, then something is resizing the parent after it's created. Check if `recalc_fit_children_sizing` is changing it.

## Quick Test

Alternatively, add this single line of debug output right before rendering (in the render loop):

```odin
// In ui.odin, after position_boxes(root) at line 404:
if box := ui_state.box_cache["hey@lllll"]; box != nil {
    printfln("Button 'hey' height just before render: {}", box.height)
}
```

This will tell you the final height of the button right before it's rendered.
