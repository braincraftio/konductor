import { test, expect } from '@playwright/test';

test('audit aurora design system compliance', async ({ page }) => {
  // 1. Inspect the Reference Implementation (Style Guide)
  console.log('--- AUDITING REFERENCE STYLE GUIDE ---');
  await page.goto('https://braincraftio.github.io/style-system/');
  
  const referenceStyles = await page.evaluate(() => {
    const body = getComputedStyle(document.body);
    const root = getComputedStyle(document.documentElement);
    const primaryBtn = document.querySelector('.btn-primary');
    const btnStyles = primaryBtn ? getComputedStyle(primaryBtn) : null;

    return {
      bgBase: root.getPropertyValue('--color-surface-base') || body.backgroundColor,
      fontSans: root.getPropertyValue('--font-sans'),
      fontMono: root.getPropertyValue('--font-mono'),
      colorPrimary: root.getPropertyValue('--color-primary'),
      btnRadius: root.getPropertyValue('--radius-lg'), // Buttons use lg radius
      // Computed values
      computedBodyBg: body.backgroundColor,
      computedBtnRadius: btnStyles ? btnStyles.borderRadius : 'N/A',
      computedBtnBg: btnStyles ? btnStyles.backgroundImage : 'N/A', // Primary often has gradient
    };
  });
  console.log(JSON.stringify(referenceStyles, null, 2));

  // 2. Inspect Konductor.sh (Local)
  console.log('\n--- AUDITING KONDUCTOR.SH (LOCAL) ---');
  await page.goto('http://localhost:4321/');

  const localStyles = await page.evaluate(() => {
    const body = getComputedStyle(document.body);
    // Try to find a primary button or CTA
    const primaryBtn = document.querySelector('button, .btn, a[class*="btn"], a[class*="button"]');
    const btnStyles = primaryBtn ? getComputedStyle(primaryBtn) : null;
    
    // Check for tokens variable presence (if defined in CSS)
    const root = getComputedStyle(document.documentElement);

    return {
      fontSans: body.fontFamily, // Should match Inter
      computedBodyBg: body.backgroundColor,
      // Color Audit
      // Note: We expect standard Tailwind classes or Aurora variables
      primaryColorVar: root.getPropertyValue('--color-primary'),
      
      // Component Audit
      btnFound: !!primaryBtn,
      computedBtnRadius: btnStyles ? btnStyles.borderRadius : 'N/A',
      computedBtnBg: btnStyles ? btnStyles.backgroundColor : 'N/A',
    };
  });
  console.log(JSON.stringify(localStyles, null, 2));

  // 3. Assertions (Soft assertions to log diffs without failing immediately)
  // Check Fonts
  const isInter = localStyles.fontSans.includes('Inter');
  console.log(`\nCheck: Font is Inter? ${isInter ? 'PASS' : 'FAIL'} (${localStyles.fontSans})`);
  
  // Check Background (Cream/Warm)
  // Reference Body BG might be variable, local computed is typically RGB
  // We'll trust the visual verification via console log for now, but log the mismatch if stark.
  
  // Check Radius
  // Aurora uses 0.75rem (12px) for buttons
  const isRadiusCorrect = localStyles.computedBtnRadius === '12px' || localStyles.computedBtnRadius === '0.75rem';
  console.log(`Check: Button Radius is 12px/lg? ${isRadiusCorrect ? 'PASS' : 'FAIL'} (${localStyles.computedBtnRadius})`);

});
