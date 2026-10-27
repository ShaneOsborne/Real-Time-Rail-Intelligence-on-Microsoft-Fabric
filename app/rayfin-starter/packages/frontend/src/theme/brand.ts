// Lab 11 – app branding in one place. Change the name, strapline and colours here; rail.css reads the colours as CSS
// variables (set in AppShell). Keep it clearly unofficial: don't use Network Rail / National Rail names or logos.
export const BRAND = {
  name: 'RailPulse',
  strapline: 'Live GB rail network intelligence · Microsoft Fabric',
  colours: {
    ink: '#0b1f3a', // header, headings
    inkSoft: '#3a4a63', // body text
    accent: '#00a3a1', // brand accent (teal)
    accentSoft: '#e6f6f6',
    surface: '#ffffff', // cards
    canvas: '#f3f5f9', // page background
    border: '#e1e6ef',
    onTime: '#107c10',
    late: '#f2a33a',
    veryLate: '#d13438',
    rail: '#5c2d91', // railway lines (Lab 11b)
  },
} as const;

export const DELAY_BANDS = [
  { key: 'onTime', label: 'On time', colour: BRAND.colours.onTime },
  { key: 'late', label: '1–14 min late', colour: BRAND.colours.late },
  { key: 'veryLate', label: '15+ min late', colour: BRAND.colours.veryLate },
] as const;

export function delayColour(delayMinutes: number): string {
  if (delayMinutes >= 15) return BRAND.colours.veryLate;
  if (delayMinutes > 0) return BRAND.colours.late;
  return BRAND.colours.onTime;
}
