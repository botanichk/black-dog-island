// GENERATED FILE - do not edit. Source: theme/templates/colors.scss.tpl
// Scheme: {{scheme}}
// Regenerate: theme/apply.sh <scheme> [--reload]
// Keep this file ASCII-only: the SCSS compiler emits "@charset" for non-ASCII
// input and GTK rejects that rule, dropping the whole stylesheet.

// --- palette roles ---
$surface: {{surface}};
$surface-container: {{surface_container}};
$surface-container-high: {{surface_high}};
$surface-highest: {{surface_highest}};
$outline: {{outline}};
$on-surface: {{on_surface}};
$on-surface-variant: {{on_surface_variant}};
$primary: {{primary}};
$primary-dim: {{primary_dim}};
$error: {{error}};
$on-primary: {{on_primary}};
$weather-cloud: {{weather_cloud}};
$weather-snow: {{weather_snow}};

// --- transparent roles (colour + alpha, assembled by apply.sh) ---
$state-hover: {{state_hover}};
$state-press: {{state_press}};
$state-selected: {{state_selected}};
$divider: {{divider}};
$on-surface-dim: {{on_surface_dim}};
$text-shadow: {{text_shadow}};
$wx-shade: {{wx_shade}};
$wx-scrim: {{wx_scrim}};
// Base colour for the per-scene darkening layer: its alpha comes from
// forecast.sh (runtime variable w-shade), the colour from the scheme.
$wx-ink: {{wx_ink}};

// --- weather card fallback gradients (scene backdrops are JPEG files) ---
$wx-clear-day-a: {{wx_clear_day_a}};
$wx-clear-day-b: {{wx_clear_day_b}};
$wx-clear-night-a: {{wx_clear_night_a}};
$wx-clear-night-b: {{wx_clear_night_b}};
$wx-cloudy-day-a: {{wx_cloudy_day_a}};
$wx-cloudy-day-b: {{wx_cloudy_day_b}};
$wx-cloudy-night-a: {{wx_cloudy_night_a}};
$wx-cloudy-night-b: {{wx_cloudy_night_b}};
$wx-rain-a: {{wx_rain_a}};
$wx-rain-b: {{wx_rain_b}};
$wx-snow-a: {{wx_snow_a}};
$wx-snow-b: {{wx_snow_b}};
$wx-fog-a: {{wx_fog_a}};
$wx-fog-b: {{wx_fog_b}};
$wx-storm-a: {{wx_storm_a}};
$wx-storm-b: {{wx_storm_b}};
