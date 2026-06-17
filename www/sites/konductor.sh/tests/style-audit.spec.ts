import { test, expect } from '@playwright/test';

test('aurora design system tokens are applied', async ({ page }) => {
  await page.goto('http://localhost:4321/');

  const styles = await page.evaluate(() => {
    const root = getComputedStyle(document.documentElement);
    const primaryBtn = document.querySelector('.btn-primary');
    const btnStyles = primaryBtn ? getComputedStyle(primaryBtn) : null;

    return {
      fontFamily: getComputedStyle(document.body).fontFamily,
      brandPrimary: root.getPropertyValue('--brand-primary').trim(),
      surfaceBase: root.getPropertyValue('--surface-base').trim(),
      btnFound: !!primaryBtn,
      btnBorderRadius: btnStyles ? btnStyles.borderRadius : 'N/A',
    };
  });

  expect(styles.fontFamily).toContain('Inter');
  expect(styles.brandPrimary).not.toBe('');
  expect(styles.surfaceBase).not.toBe('');
  expect(styles.btnFound).toBe(true);
});
