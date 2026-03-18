# Test Suite Documentation

## Test Files Created

### 1. layout_margin_tests.odin
Tests for margin implementation in the layout system.
- ✅ All tests passing (11 tests)
- Tests children's margins in fit_children calculations
- Tests margin positioning in horizontal/vertical layouts
- Tests margin with padding interactions
- Tests floating children are ignored
- Tests helper functions for margin/padding totals

### 2. layout_grow_tests.odin
Tests for grow sizing with margins.
- ✅ All tests passing (8 tests)
- Tests grow sizing in horizontal/vertical layouts with margins
- Tests multiple growable children
- Tests cross-axis grow
- Tests Fit_Text_And_Grow and Fit_Children_And_Grow with margins
- Tests margins don't interfere with gap calculations

### 3. layout_alignment_tests.odin
Tests for alignment and positioning with margins.
- ✅ All tests passing (12 tests)
- Tests horizontal/vertical center, end, space_around, space_between alignments
- Tests cross-axis alignments
- Tests all combinations of main and cross axis positioning

### 4. layout_percent_tests.odin
Tests for percent sizing.
- ✅ All tests passing (8 tests)
- Tests basic percent width/height sizing
- Tests multiple children with percent sizing
- Tests percent with padding
- Tests nested percent sizing
- Tests percent ignores floating children

### 5. layout_mixed_sizing_tests.odin
Tests for mixed sizing modes.
- ✅ All tests passing (10 tests)
- Tests mixing Fixed and Grow sizing
- Tests mixing Fit_Children and Grow
- Tests all sizing modes together
- Tests Fit_Text with other modes
- Tests empty/single child containers
- Tests grow with unequal initial sizes

### 6. layout_edge_cases_tests.odin
Tests for edge cases and corner cases.
- ✅ All tests passing (22 tests)
- Tests gap calculations with no/single/multiple children
- Tests all floating children
- Tests mixed floating and normal children
- Tests very small and zero-sized children
- Tests asymmetric padding/margins
- Tests widest/tallest child selection
- Tests helper functions with zeros
- Tests deeply nested layouts

### 7. layout_grow_distribution_tests.odin
Tests for grow distribution algorithm.
- ✅ All tests passing (10 tests)
- Tests equal distribution among children with same grow amount
- Tests weighted distribution with different grow amounts (1.0, 2.0, 3.0)
- Tests grow with margins and gaps
- Tests grow mixed with fixed children
- Tests vertical grow
- Tests grow ignores floating children
- Tests Fit_Children_And_Grow sizing mode
- Tests three children with weighted distribution

### 8. layout_nested_tests.odin
Tests for complex nested layout scenarios.
- ✅ All tests passing (7 tests)
- Tests horizontal container nested in vertical parent
- Tests deeply nested fit_children (3 levels)
- Tests nested margins propagating through hierarchy
- Tests nested percent sizing (grandparent -> parent -> child)
- Tests grow inside fit_children parent
- Tests alternating layout directions (H->V->H)

### 9. layout_pathological_tests.odin
Extreme edge cases and pathological scenarios that stress-test the system limits.
- ✅ All tests passing (18 tests)
- Tests 10-level deep nesting
- Tests 100 children in single container
- Tests extreme grow amounts (100.0 vs 1.0, and 0.01 tiny amounts)
- Tests extreme percent values (0.00001%, 150%)
- Tests padding/margins larger than content
- Tests gap larger than all children combined
- Tests single-pixel sizes throughout entire hierarchy
- Tests extreme aspect ratios (10000x1 and 1x10000)
- Tests alternating huge (1000px) and tiny (1px) children
- Tests rounding errors with 7 children at 1/7 percent each
- Tests grow with zero available space
- Tests nested chaos (all sizing modes in one hierarchy)
- Tests overflow (children larger than parent space)
- Tests zero percent edge case
- Tests gap-dominated layouts (gaps >> children sizes)

## Bugs Found and Fixed

### Gap Calculation with Empty Containers
Found bug in `sizing_calc_fit_children_width` and `sizing_calc_fit_children_height` at [core.odin:783-786](../core.odin#L783-L786) and [core.odin:828-831](../core.odin#L828-L831). When `num_of_non_floating_children` returned 0, the expression `gap * (0 - 1)` resulted in negative gap values being subtracted from the total. Fixed by only applying gap calculation when there are 2 or more children.

### Percent Sizing Applied to Floating Children
Found bug in `sizing_calc_percent_width` and `sizing_calc_percent_height` at [core.odin:1020](../core.odin#L1020) and [core.odin:1045](../core.odin#L1045). Percent sizing was being applied to all children regardless of `floating_type`. Fixed by adding check for `.Not_Floating` before applying percent sizing.

## Test Coverage Summary

**Total: 94 tests, all passing**

### ✅ Comprehensively Tested
- **Fit_Children sizing** - Width/height calculations, with margins, padding, gaps
- **Grow sizing** - Distribution algorithm, weighted grow amounts, with margins/gaps
- **Percent sizing** - Basic and nested, with padding, ignoring floats
- **Alignment modes** - Start, Center, End, Space_Around, Space_Between on both axes
- **Mixed sizing modes** - All combinations of Fixed, Grow, Fit_Children, Percent
- **Margins and padding** - Correct inclusion in calculations and propagation through nesting
- **Gaps** - Horizontal/vertical, edge cases with 0/1/multiple children
- **Floating children** - Correctly ignored in all layout calculations
- **Edge cases** - Empty containers, single child, zero sizes, asymmetric spacing
- **Nested layouts** - Multi-level hierarchies, alternating directions, margin propagation
- **Grow distribution** - Equal and weighted distribution, interaction with fixed children
- **Pathological cases** - Extreme nesting (10 levels), extreme values (0.00001% to 150%), extreme counts (100 children), extreme aspect ratios (10000:1), size mismatches, rounding errors, overflow scenarios

### ❌ Not Yet Tested
- Absolute/floating positioning calculations (internal functions not exposed)
- Min/max size constraints
- Fit_Text and Fit_Text_And_Grow with actual text measurement
- Z-index flow and inheritance
- Full layout pipeline integration (complete size_boxes -> position_boxes flow)
- Text wrapping and text sizing
- Signal handling (clicks, hover, drag, etc.)
