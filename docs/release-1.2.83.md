# Android 1.2.83 (100) และภาพหน้าจอเว็บไซต์ปัจจุบัน

เจ้าของอนุญาตให้ปล่อยอัปเดตและเปลี่ยนภาพหน้าจอแอปบนเว็บไซต์ทั้งหมด
รุ่นนี้ทำให้ปุ่มทานที่ร้าน/สั่งกลับบ้านมีพื้นผิวทึบ ขอบชัด และเงาบางตามธีม
คงเส้นทางการขายและตะกร้าเดิม พร้อมภาพหน้าจอ 5 หน้ารุ่นปัจจุบันบนเว็บ 9 หน้า

สถานะ: เผยแพร่เว็บ/APK แล้ว 22 พฤศจิกายน 2026 เวลา 14:23 AEDT
ติดตั้งและตรวจบน SM-X900 แล้ว ตรวจไฟล์/หน้าจอจากเว็บจริงผ่านเวลา 14:24 AEDT

## หลักฐานก่อนปล่อย

- Native source `f5b8cf51dbd962caeda021f2235ab0760ab2566a`;
  ตรวจ 422 native inputs ตรง Git ก่อน/หลัง build และตอน staging
- Signed APK package `app.pokpok.pos`, 1.2.83/100, 93,116,248 bytes;
  SHA-256 `1d87f9af7bb1cf819bf8ccf82c0d1d5756ef346122dd1c6ac311327f580ba3f6`
  signer เดียวกับรุ่น 99, native libapp เปลี่ยนครบ 3 ABIs, build receipt ผ่าน
- 9 existing UX workflow tests ผ่าน และ targeted analysis ของหน้าที่แก้ผ่าน
  มีการ render ตรวจอีก 8 ภาพ (1440/768/390/320, สว่าง/มืด, 320 ที่ text 200%)
  ค่า contrast ขอบ/พื้นหลังเพิ่มเป็น 3.97:1 และ 5.56:1 ตามลำดับ
- Fresh Codex CLI review แบบ ephemeral/read-only ไม่รับบทสนทนาของผู้สร้าง
  ใช้ gpt-6.2-sol/xhigh เป็น fallback เนื่องจาก Grok/Claude ไม่พร้อมใช้งาน
  ตรวจ native delta ตั้งแต่ public release fa1eb3e ถึง f5b8cf5 ไม่พบ defect ใหม่
  ใน production themes; focus overlay ยังทำงาน แม้ fallback MaterialApp ที่
  ไม่ใช้ธีมแอปจะไม่ได้เปลี่ยนสีขอบ focus แบบ stock เดิม ข้อนี้ไม่ใช่ production path
- Device install -r สำเร็จ อ่าน package กลับเป็น 1.2.83/100 เปิดทั้งทานที่ร้าน
  และสั่งกลับบ้าน เพิ่ม 3 รายการในตะกร้าชั่วคราวแล้วลบออกทั้งหมด กลับ chooser
  ไม่ชำระเงิน บันทึกโต๊ะ หรือเปลี่ยนออเดอร์/สต็อก
- ภาพ 4 หน้าเป็น screencap จากแท็บเล็ตรุ่น 100; ภาพครัวเป็น widget รุ่นเดียวกัน
  กับข้อมูลสาธิตแยกจากระบบจริง ระบุใต้ภาพแล้ว รายละเอียดและ hash ใน
  `docs/website-screenshots-2026-11-22.md`
- เว็บผ่าน 18 หน้า × 5 widths และ homepage 13 กลุ่มที่ 8 widths
  รวมลิงก์/ภาพ เมนู ราคา guide flows, swipe, keyboard, no-JS และ image failure
- ภาพครัว render จาก source/assets ตรงกันทั้ง 236 ไฟล์; ภาพ WebP สี่ภาพรวม
  139,316 bytes รายการ hash ที่ `docs/previews/website-screens-1.2.83.json`

## ผลตรวจและข้อจำกัด

Fresh website source review ตรวจทั้ง native/web delta และภาพ 9 ไฟล์:
เส้นทางภาพและ variants/fallbacks/metadata/privacy ผ่าน พบ Medium เรื่อง caption
ครัวไม่แยกวิธีสร้างภาพชัดพอ แก้ทั้งสองจุดเป็น “ภาพเรนเดอร์หน้าครัว” และ alt
ระบุว่า render พร้อมข้อมูลสาธิต ไม่อ้างเป็นภาพถ่ายแท็บเล็ต

Low ที่คงไว้: คู่มือออเดอร์ใช้ภาพหมวดรอยืนยันที่ว่าง จึงไม่แสดงตัวอย่างปุ่ม
รายละเอียด/ชำระเงินใต้แต่ละรายการ คำบรรยายระบุสถานะว่างจริง ช่วยบอกตำแหน่ง
เมนูและตัวกรอง แต่ยังต้องอ่านขั้นตอนประกอบ เลือกหลีกเลี่ยงการเผยข้อมูลลูกค้า
หรือสร้างออเดอร์ลงระบบเพื่อถ่ายภาพ รอบถัดไปที่มีงานขยายคู่มือใช้ข้อมูลสาธิตแยก
เพื่อเพิ่มตัวอย่างรายละเอียดออเดอร์ โดยไม่ย้อนใช้ภาพรุ่นเก่า

Visual walkthrough อ่าน 14 ภาพที่ 1440/768/390: ไม่มีภาพถูกตัดหรือขยายเกินกรอบ
คำบรรยายกับภาพตรงกัน มีลิงก์เปิดขนาดเต็มทุกจุด ข้อจำกัดที่เห็น: รายละเอียด
แท็บเล็ตเล็กบนมือถือ, ตัวอย่างสินค้าอาหารไม่เฉพาะมินิมาร์ท และวันที่อ้างอิง
เนื้อหาคู่มือยังเก่ากว่าวันถ่ายภาพ (ตั้งใจคงไว้เพราะไม่ได้ตรวจทุกขั้นตอนใหม่)
ทั้งหมดเป็นข้อจำกัดการนำเสนอเดิม/ตัวอย่าง ไม่ใช่หลักฐานว่ามีการตรวจคู่มือรุ่นใหม่
ผู้ดูภาพต้องอ่าน HANDOFF/ข้อกำหนดเว็บก่อนตามกฎโครงการ จึงไม่ใช่ fully blind

Focused design audit 17/20: accessibility 3, performance 3, theming 4,
responsive 3, implementation integrity 4; ไม่มี P0/P1 ในส่วนที่เปลี่ยน
ภาพย่อมี alt/ขนาด/ลิงก์ขยาย; PNG เต็มใหญ่กว่า WebP แต่แสดงแบบ lazy ในส่วนล่าง
ไม่เปลี่ยนสีธีมหรือเลย์เอาต์เว็บ รูปและข้อความคำอธิบายตรง source/version

## การเผยแพร่

Candidate `fea2e0f` ผ่าน fresh caption follow-up review (ไม่พบ defect ใหม่)
และ marketing gate รอบสุดท้าย 18 หน้า × 5 widths แล้ว Hosting preflight พบ
21 public-file changes ตามรายการที่กำหนด และ config/live baseline ตรงเดิม
ใช้คำอนุญาตเผยแพร่ที่เจ้าของให้ในคำขอนี้ เดินหน้าตามขอบเขตดังต่อไปนี้
เป้าหมาย Firebase Hosting project `shop-pos-89294`, เว็บ `https://pok-pok.app`
เผยแพร่เฉพาะ Hosting (APK/manifest/ภาพและการอ้างภาพ) ไม่ deploy backend/iOS
ไม่เปลี่ยน Hosting config, payment mode หรือ security enforcement

Rollback: Hosting version `c698ab63be2f8a3b` (Android 1.2.82/99 และภาพเดิม)
ผลหลัง deploy:

- Release source `2381f3cd2e7fafe37a7f122d0f051d3c7394bfc1` ตรง origin/master
  ก่อน deploy; Hosting version `e9fc85e582067d26`, 03:23 UTC / 14:23 AEDT
- Cloud file hashes ทั้ง 101 ไฟล์ตรง local release; config เหมือน baseline
- ดาวน์โหลด APK เต็มจากโดเมนจริงเวลา 03:24:23 UTC ตรง size/digest ข้างต้น
  manifest ให้ 1.2.83/100 และไฟล์เว็บที่เปลี่ยนอีก 20 ไฟล์ตรง byte hash ทั้งหมด
- Live Chromium ตรวจ 9 หน้า × 1440/768/390 ผ่าน current PNG/WebP, ลิงก์เต็ม,
  metadata, restaurant/retail story variants; ไม่มี overflow หรือ page error
- ไม่ได้ทดสอบเว็บบน physical tablet; การตรวจอุปกรณ์จริงครอบคลุม native app
- เก็บ APK เดิมและ Hosting baseline สำหรับ rollback ไม่มี backend/iOS update

หลักฐานภายนอก Git: `D:/pokpok-release-1.2.83/`
