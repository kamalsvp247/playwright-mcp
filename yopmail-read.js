const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  const page = await browser.newPage();
  try {
    await page.goto('https://yopmail.com/en/?login=ranakhansvp2465', { waitUntil: 'domcontentloaded', timeout: 60000 });
  } catch (e) { console.log('goto warn:', e.message); }
  await page.waitForTimeout(6000);

  let frames = page.frames();
  let inbox = frames.find(f => f.url().includes('inbox'));
  if (!inbox) {
    await page.waitForTimeout(5000);
    frames = page.frames();
    inbox = frames.find(f => f.url().includes('inbox'));
  }
  if (!inbox) { console.log('NO INBOX FRAME'); await browser.close(); return; }

  const first = await inbox.evaluate(() => {
    const el = document.querySelector('.m');
    return el ? { id: el.id, text: (el.textContent || '').replace(/\s+/g, ' ').trim() } : null;
  });
  console.log('LATEST:', JSON.stringify(first));

  if (first) {
    const msgPage = await browser.newPage();
    await msgPage.goto('https://yopmail.com/en/mail?b=ranakhansvp2465&id=' + first.id, { waitUntil: 'domcontentloaded', timeout: 60000 }).catch(e => console.log('msg goto warn:', e.message));
    await msgPage.waitForTimeout(4000);
    const text = await msgPage.evaluate(() => {
      const main = document.querySelector('#mail');
      return main ? (main.textContent || '').replace(/\s+/g, ' ').trim() : (document.body.textContent || '').replace(/\s+/g, ' ').trim();
    });
    console.log('MESSAGE_BODY:', text.slice(0, 2500));
    const codes = text.match(/\b\d{4,8}\b/g) || [];
    console.log('POSSIBLE_CODES:', JSON.stringify(codes));
    await msgPage.close().catch(() => {});
  }
  await browser.close();
})();
