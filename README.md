# PDF Reader Pro Pack (Flutter, Android)
ชุดไฟล์พร้อมใช้สำหรับสร้าง APK ออนไลน์ผ่าน GitHub Actions — รองรับ:
- จำหน้าที่อ่านล่าสุด
- บุ๊คมาร์ก (เพิ่ม/ลบ/กระโดดไปหน้า)
- ไฮไลท์/จดโน้ต (บันทึกข้อความที่เลือก + หน้า) — เก็บใน Firestore/โลคัล
- ซูมอ่านจุดที่แตะ (ดับเบิลแท็ป)

> ถ้าไม่ตั้งค่า Firebase/Keystore จะได้ **debug APK** สำหรับทดสอบก่อน

## โครงสร้าง
- `pubspec.yaml` — รายการ dependencies ของ Pro
- `lib/main.dart` — โค้ดหลัก
- `.github/workflows/build-android-pro.yml` — เวิร์กโฟลว์สร้าง APK ออนไลน์
- `android/app/google-services.json.placeholder` — ไฟล์หลอก (อธิบายวิธีใช้ Secret)

## วิธีใช้แบบเร็วสุด
1) สร้าง GitHub repo ใหม่ แล้วอัปโหลดทั้งโฟลเดอร์นี้ขึ้นไป (รวมโฟลเดอร์ `.github/workflows/`)  
2) ไปแท็บ **Actions** → เลือก workflow **Build Android APK (PRO)** → **Run workflow**  
3) ถ้ายังไม่ได้ตั้งค่าซิงก์/เซ็น จะได้ **app-debug.apk** ใน Artifacts (ติดตั้งทดสอบได้ทันที)

## เปิดใช้ซิงก์ Firebase (สำหรับโปร)
1) สร้างโปรเจกต์ใน Firebase Console → เพิ่ม Android app (package name เริ่มต้นจาก `flutter create` เป็น `com.example.pdf_reader_pro` ปรับได้)  
2) ดาวน์โหลด `google-services.json`  
3) ไปที่ **GitHub → Settings → Secrets → Actions** สร้าง Secret ชื่อ `FIREBASE_JSON` แล้ว **วางเนื้อ JSON ของไฟล์** ลงไปตรงๆ  
4) (Workflow มีขั้น patch ปลั๊กอิน `com.google.gms.google-services` ใส่ใน `app/build.gradle` ให้อัตโนมัติ)

## สร้าง Release APK (ลงนามและแยก ABI)
1) สร้าง keystore (ออนไลน์ผ่าน Codespaces ก็ได้) → เข้ารหัส base64  
2) ใส่ Secrets:  
   - `ANDROID_KEYSTORE_BASE64`  
   - `ANDROID_KEYSTORE_PASSWORD`  
   - `ANDROID_KEY_ALIAS` (เช่น `upload`)  
   - `ANDROID_KEY_ALIAS_PASSWORD`  
3) รัน workflow อีกครั้ง → จะได้ `app-arm64-v8a-release.apk` ฯลฯ

## ใส่ไลเซนส์ Syncfusion (ถ้าใช้)
- ตั้ง Secret `SYNCFUSION_LICENSE`  
- โค้ดอ่านค่าแบบ `const _sfl = String.fromEnvironment('SYNCFUSION_LICENSE')` และเรียก `SyncfusionLicense.registerLicense(_sfl)`

## หมายเหตุเรื่องไฮไลท์/โน้ต
- โค้ดตัวอย่างจะ **บันทึกข้อความที่เลือก + หน้า** ลง Firestore/โลคัล และแสดงเป็น “รายการไฮไลท์/โน้ต” ให้กดกระโดดหน้าได้
- (ไม่แก้ไขตัว PDF ต้นฉบับ) ถ้าต้องการ “ฝังไฮไลท์ลงไฟล์ PDF” จริง ๆ ให้ใช้ไลบรารี PDF ระดับแก้เอกสาร และปรับโค้ดส่วน export เพิ่มเติม

## ทดสอบติดตั้ง APK
- ดาวน์โหลดจาก Artifacts แล้วส่งไฟล์ไปยังเครื่อง Android → ติดตั้ง (อนุญาตติดตั้งจากแหล่งที่ไม่รู้จัก)
