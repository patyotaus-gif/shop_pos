# Android 1.2.83 (100) และภาพหน้าจอเว็บไซต์ปัจจุบัน

เจ้าของอนุญาตให้ปล่อยอัปเดตและเปลี่ยนภาพหน้าจอแอปบนเว็บไซต์ทั้งหมด
รุ่นนี้ทำให้ปุ่มทานที่ร้าน/สั่งกลับบ้านมีพื้นผิวทึบ ขอบชัด และเงาบางตามธีม
คงเส้นทางการขายและตะกร้าเดิม พร้อมภาพหน้าจอ 5 หน้ารุ่นปัจจุบันบนเว็บ 9 หน้า

สถานะ: ติดตั้งและตรวจบน SM-X900 แล้ว เตรียมเผยแพร่เว็บ/APK

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

## การเผยแพร่

กำลังเตรียม source commit, fresh website review และ Hosting preflight
เป้าหมาย Firebase Hosting project `shop-pos-89294`, เว็บ `https://pok-pok.app`
เผยแพร่เฉพาะ Hosting (APK/manifest/ภาพและการอ้างภาพ) ไม่ deploy backend/iOS
ไม่เปลี่ยน Hosting config, payment mode หรือ security enforcement

Rollback: Hosting version `c698ab63be2f8a3b` (Android 1.2.82/99 และภาพเดิม)
หลัง deploy ต้องตรวจ cloud file hashes/config, ดาวน์โหลด APK เต็มตรวจ digest,
ตรวจทุกไฟล์เว็บที่เปลี่ยนและ browser smoke จากโดเมนจริงก่อนถือว่าเสร็จ

หลักฐานภายนอก Git: `D:/pokpok-release-1.2.83/`
