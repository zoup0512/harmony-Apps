import { common } from '@kit.AbilityKit';

export const PREFS_NAME = 'com.razor.cams_preferences';
export const KEY_THEME_MODE = 'appearance_theme_mode';
export const DEFAULT_ACCENT = '#20B486';

export interface NvrColors {
  primary: string;
  onPrimary: string;
  primaryContainer: string;
  onPrimaryContainer: string;
  secondary: string;
  onSecondary: string;
  background: string;
  onBackground: string;
  surface: string;
  onSurface: string;
  surfaceVariant: string;
  onSurfaceVariant: string;
  outline: string;
  outlineVariant: string;
  error: string;
  secondaryContainer: string;
  placeholderColor: string;
}

export function buildLightColors(): NvrColors {
  return {
    primary: '#20B486',
    onPrimary: '#FFFFFF',
    primaryContainer: '#D6F3E8',
    onPrimaryContainer: '#20B486',
    secondary: '#1A9E73',
    onSecondary: '#FFFFFF',
    background: '#F7F8FA',
    onBackground: '#1B1B1D',
    surface: '#FFFFFF',
    onSurface: '#1B1B1D',
    surfaceVariant: '#F0F1F5',
    onSurfaceVariant: '#6B6F76',
    outline: '#E0E2E8',
    outlineVariant: '#E8E9ED',
    error: '#E53935',
    secondaryContainer: '#D6F3E8',
    placeholderColor: '#A8ACB3',
  };
}

export function buildDarkColors(): NvrColors {
  return {
    primary: '#20B486',
    onPrimary: '#000000',
    primaryContainer: '#1A3D31',
    onPrimaryContainer: '#20B486',
    secondary: '#1A9E73',
    onSecondary: '#000000',
    background: '#121316',
    onBackground: '#E6E6E9',
    surface: '#1B1D21',
    onSurface: '#E6E6E9',
    surfaceVariant: '#272A30',
    onSurfaceVariant: '#9AA0A8',
    outline: '#3A3D44',
    outlineVariant: '#2D3035',
    error: '#EF5350',
    secondaryContainer: '#1A3D31',
    placeholderColor: '#5A5F66',
  };
}

export class AppearanceThemeState {
  static themeMode: string = 'light';

  static update(mode: string): void {
    AppearanceThemeState.themeMode = mode;
  }

  static initFromPrefs(prefsMode: string): void {
    AppearanceThemeState.themeMode = prefsMode || 'light';
  }
}

export function isDarkMode(themeMode: string, systemColorMode: 'light' | 'dark'): boolean {
  if (themeMode === 'system') return systemColorMode === 'dark';
  return themeMode === 'dark';
}

export function getColors(themeMode: string, systemColorMode: 'light' | 'dark'): NvrColors {
  return isDarkMode(themeMode, systemColorMode) ? buildDarkColors() : buildLightColors();
}
