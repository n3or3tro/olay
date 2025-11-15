import {
    argbFromHex,
    hexFromArgb,
    TonalPalette,
    CorePalette,
    Scheme,
    SchemeContent,
    SchemeExpressive,
    SchemeMonochrome,
    SchemeTonalSpot,
    SchemeFidelity,
    DynamicScheme,
    DynamicColor,
    MaterialDynamicColors,
    Hct
} from '@material/material-color-utilities';

import { writeFile } from 'fs/promises';

// Your base color structure
const baseColors = {
    primary: '#6750A4',    // Purple
    secondary: '#625B71',  // Muted purple
    tertiary: '#7D5260',   // Pink-ish
    neutral: '#605D62',    // Gray
    surface: '#FFFBFE',    // Light surface
    surfaceVariant: '#E7E0EC',
    inactive: '#CAC4D0',
    warning: '#F9A825',    // Amber
    error: '#BA1A1A'       // Red
};

// Convert hex colors to ARGB format
function hexToArgb(hex) {
    return argbFromHex(hex);
}

// Create a custom theme generator
function generateThemeTokens(baseColors, isDark = false) {
    // Convert base colors to ARGB
    const primaryArgb = hexToArgb(baseColors.primary);
    const secondaryArgb = hexToArgb(baseColors.secondary);
    const tertiaryArgb = hexToArgb(baseColors.tertiary);
    const neutralArgb = hexToArgb(baseColors.neutral);
    const errorArgb = hexToArgb(baseColors.error);

    // Create tonal palettes from your base colors
    const primaryPalette = TonalPalette.fromInt(primaryArgb);
    const secondaryPalette = TonalPalette.fromInt(secondaryArgb);
    const tertiaryPalette = TonalPalette.fromInt(tertiaryArgb);
    const neutralPalette = TonalPalette.fromInt(neutralArgb);
    const neutralVariantPalette = TonalPalette.fromInt(hexToArgb(baseColors.surfaceVariant));
    const errorPalette = TonalPalette.fromInt(errorArgb);

    // Create a CorePalette with your custom palettes
    const corePalette = CorePalette.of(primaryArgb);
    // Override with custom palettes
    corePalette.a1 = primaryPalette;
    corePalette.a2 = secondaryPalette;
    corePalette.a3 = tertiaryPalette;
    corePalette.n1 = neutralPalette;
    corePalette.n2 = neutralVariantPalette;
    corePalette.error = errorPalette;

    // Generate scheme (light or dark)
    const scheme = isDark ?
        Scheme.darkFromCorePalette(corePalette) :
        Scheme.lightFromCorePalette(corePalette);

    // Add custom warning color
    const warningPalette = TonalPalette.fromInt(hexToArgb(baseColors.warning));
    const warningTone = isDark ? 80 : 40;
    const onWarningTone = isDark ? 20 : 100;
    const warningContainerTone = isDark ? 30 : 90;
    const onWarningContainerTone = isDark ? 90 : 10;

    // Create comprehensive semantic token mapping
    const semanticTokens = {
        // Primary colors
        primary: hexFromArgb(scheme.primary),
        onPrimary: hexFromArgb(scheme.onPrimary),
        primaryContainer: hexFromArgb(scheme.primaryContainer),
        onPrimaryContainer: hexFromArgb(scheme.onPrimaryContainer),

        // Secondary colors
        secondary: hexFromArgb(scheme.secondary),
        onSecondary: hexFromArgb(scheme.onSecondary),
        secondaryContainer: hexFromArgb(scheme.secondaryContainer),
        onSecondaryContainer: hexFromArgb(scheme.onSecondaryContainer),

        // Tertiary colors
        tertiary: hexFromArgb(scheme.tertiary),
        onTertiary: hexFromArgb(scheme.onTertiary),
        tertiaryContainer: hexFromArgb(scheme.tertiaryContainer),
        onTertiaryContainer: hexFromArgb(scheme.onTertiaryContainer),

        // Error colors
        error: hexFromArgb(scheme.error),
        onError: hexFromArgb(scheme.onError),
        errorContainer: hexFromArgb(scheme.errorContainer),
        onErrorContainer: hexFromArgb(scheme.onErrorContainer),

        // Warning colors (custom)
        warning: hexFromArgb(warningPalette.tone(warningTone)),
        onWarning: hexFromArgb(warningPalette.tone(onWarningTone)),
        warningContainer: hexFromArgb(warningPalette.tone(warningContainerTone)),
        onWarningContainer: hexFromArgb(warningPalette.tone(onWarningContainerTone)),

        // Background colors
        background: hexFromArgb(scheme.background),
        onBackground: hexFromArgb(scheme.onBackground),

        // Surface colors
        surface: hexFromArgb(scheme.surface),
        onSurface: hexFromArgb(scheme.onSurface),
        surfaceVariant: hexFromArgb(scheme.surfaceVariant),
        onSurfaceVariant: hexFromArgb(scheme.onSurfaceVariant),

        // Surface levels (elevation)
        surfaceDim: hexFromArgb(scheme.surfaceDim),
        surfaceBright: hexFromArgb(scheme.surfaceBright),
        surfaceContainerLowest: hexFromArgb(scheme.surfaceContainerLowest),
        surfaceContainerLow: hexFromArgb(scheme.surfaceContainerLow),
        surfaceContainer: hexFromArgb(scheme.surfaceContainer),
        surfaceContainerHigh: hexFromArgb(scheme.surfaceContainerHigh),
        surfaceContainerHighest: hexFromArgb(scheme.surfaceContainerHighest),

        // Outline colors
        outline: hexFromArgb(scheme.outline),
        outlineVariant: hexFromArgb(scheme.outlineVariant),

        // Other semantic tokens
        inverseSurface: hexFromArgb(scheme.inverseSurface),
        inverseOnSurface: hexFromArgb(scheme.inverseOnSurface),
        inversePrimary: hexFromArgb(scheme.inversePrimary),
        scrim: hexFromArgb(scheme.scrim),
        shadow: hexFromArgb(scheme.shadow),

        // Custom inactive state
        inactive: baseColors.inactive,
        onInactive: isDark ? '#FFFFFF' : '#000000',
    };

    return semanticTokens;
}

// Generate both light and dark themes
let lightTheme = generateThemeTokens(baseColors, false);
let darkTheme = generateThemeTokens(baseColors, true);

console.log('Light Theme:', lightTheme);
console.log('Dark Theme:', darkTheme);

// Example: Generate tonal variations for more control
function generateTonalVariations(hexColor, name) {
    const argb = hexToArgb(hexColor);
    const palette = TonalPalette.fromInt(argb);

    // Generate a range of tones (0 = black, 100 = white)
    const tones = [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 99, 100];
    const variations = {};

    tones.forEach(tone => {
        variations[`${name}${tone}`] = hexFromArgb(palette.tone(tone));
    });

    return variations;
}

// Generate tonal variations for each base color
// const tonalVariations = {
//   primary: generateTonalVariations(baseColors.primary, 'primary'),
//   secondary: generateTonalVariations(baseColors.secondary, 'secondary'),
//   tertiary: generateTonalVariations(baseColors.tertiary, 'tertiary'),
//   neutral: generateTonalVariations(baseColors.neutral, 'neutral'),
//   error: generateTonalVariations(baseColors.error, 'error'),
//   warning: generateTonalVariations(baseColors.warning, 'warning'),
// };



function convertToJson() {
    function camelToSnake(to_convert) {
        return to_convert.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toLowerCase();
    }
    darkTheme = Object.fromEntries(Object.entries(darkTheme).map(([k, v]) => [camelToSnake(k), v]))

    // lightTheme = Object.fromEntries(Object.entires(darkTheme).map(([k, v]) => [camelToSnake(k), v])) 

    return JSON.stringify(darkTheme, null, 2);
}

let jsonData = convertToJson(darkTheme)
writeFile("dark-theme.json", jsonData)