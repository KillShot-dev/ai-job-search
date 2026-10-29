/* FileRadar demo — sample library.
   Entirely invented sample data for the demo. No real user files.
   Sizes are in MB (one decimal where shown). Dates are ISO dates.
   "text" is the searchable embedded text for a file (OCR / document text).
   Nothing here leaves the browser; there is no upload in this demo. */
window.FILERADAR_SAMPLES = [
  // ---- Images (12) ----
  { id: "img01", name: "Golden Hour at Pier 39.jpg", kind: "Images", sizeMB: 8.4, date: "2026-10-20", tags: ["vacation", "sunset", "san francisco"], source: "iPhone", location: "Pictures", dimensions: "4032 × 3024", camera: "iPhone 16 Pro", text: "pier sunset san francisco golden hour waterfront" },
  { id: "img02", name: "Screenshot 2026-10-24 at 9.41 AM.png", kind: "Images", sizeMB: 2.1, date: "2026-10-24", tags: ["screenshot", "receipt"], source: "Screenshot", location: "Desktop", dimensions: "2880 × 1800", camera: "", text: "order confirmation total 42.50 shipping receipt screenshot", hasText: true },
  { id: "img03", name: "Alpine Lake Panorama.jpg", kind: "Images", sizeMB: 24.6, date: "2026-09-12", tags: ["vacation", "mountains", "landscape"], source: "Camera", location: "Pictures", dimensions: "6000 × 4000", camera: "Sony A7 IV", text: "alpine lake mountains panorama hiking" },
  { id: "img04", name: "Product Shot — Ceramic Mug.jpg", kind: "Images", sizeMB: 12.2, date: "2026-10-15", tags: ["work", "product"], source: "Camera", location: "Documents/Projects", dimensions: "4000 × 3000", camera: "Sony A7 IV", text: "ceramic mug product photography studio" },
  { id: "img05", name: "Screenshot — Flight Itinerary.png", kind: "Images", sizeMB: 1.8, date: "2026-10-22", tags: ["screenshot", "travel"], source: "Screenshot", location: "Desktop", dimensions: "2560 × 1600", camera: "", text: "flight itinerary sfo lax departure gate boarding pass", hasText: true },
  { id: "img06", name: "Garden in Spring.jpg", kind: "Images", sizeMB: 6.9, date: "2026-04-18", tags: ["garden", "flowers"], source: "iPhone", location: "Pictures", dimensions: "4032 × 3024", camera: "iPhone 16 Pro", text: "garden spring tulips flowers backyard" },
  { id: "img07", name: "Portrait — Maya at the Studio.jpg", kind: "Images", sizeMB: 9.7, date: "2026-08-03", tags: ["portrait", "work"], source: "Camera", location: "Pictures", dimensions: "3500 × 5250", camera: "Canon EOS R6", text: "portrait studio lighting maya" },
  { id: "img08", name: "Whiteboard Notes — Q3 Planning.jpg", kind: "Images", sizeMB: 4.3, date: "2026-07-21", tags: ["whiteboard", "work"], source: "iPhone", location: "Documents/Projects", dimensions: "4032 × 3024", camera: "iPhone 16 Pro", text: "q3 planning roadmap launch whiteboard notes", hasText: true },
  { id: "img09", name: "Sunset Timelapse Still.jpg", kind: "Images", sizeMB: 11.0, date: "2026-10-25", tags: ["sunset", "timelapse"], source: "iPhone", location: "Pictures", dimensions: "4032 × 3024", camera: "iPhone 16 Pro", text: "sunset timelapse sky clouds evening" },
  { id: "img10", name: "Apartment Layout Sketch.png", kind: "Images", sizeMB: 3.2, date: "2026-05-30", tags: ["home", "sketch"], source: "Safari", location: "Downloads", dimensions: "2400 × 1800", camera: "", text: "apartment floor plan layout sketch living room kitchen", hasText: true },
  { id: "img11", name: "Birthday Cake Close-up.jpg", kind: "Images", sizeMB: 7.5, date: "2026-03-08", tags: ["birthday", "family"], source: "iPhone", location: "Pictures", dimensions: "4032 × 3024", camera: "iPhone 16 Pro", text: "birthday cake candles celebration family" },
  { id: "img12", name: "Trail Map Photo.jpg", kind: "Images", sizeMB: 5.1, date: "2026-06-27", tags: ["hiking", "map"], source: "iPhone", location: "Pictures", dimensions: "3024 × 4032", camera: "iPhone 16 Pro", text: "trail map hiking route elevation summit", hasText: true },

  // ---- Videos (7) ----
  { id: "vid01", name: "Family Picnic — June.mp4", kind: "Videos", sizeMB: 842, date: "2026-06-14", tags: ["family", "picnic"], source: "iPhone", location: "Movies", duration: "4:32", dimensions: "3840 × 2160", text: "family picnic park june summer" },
  { id: "vid02", name: "Screen Recording — App Demo.mov", kind: "Videos", sizeMB: 318, date: "2026-10-19", tags: ["work", "demo"], source: "Screen Recording", location: "Desktop", duration: "6:18", dimensions: "2560 × 1440", text: "app demo screen recording walkthrough" },
  { id: "vid03", name: "Drone Over the Coast.mp4", kind: "Videos", sizeMB: 1430, date: "2026-09-05", tags: ["drone", "coast", "vacation"], source: "Camera", location: "Movies", duration: "12:04", dimensions: "3840 × 2160", text: "drone coast ocean cliffs aerial" },
  { id: "vid04", name: "Birthday Toast.mp4", kind: "Videos", sizeMB: 96, date: "2026-03-08", tags: ["birthday", "family"], source: "iPhone", location: "Movies", duration: "1:12", dimensions: "1920 × 1080", text: "birthday toast celebration speech" },
  { id: "vid05", name: "Tutorial — Sourdough Starter.mp4", kind: "Videos", sizeMB: 512, date: "2026-02-11", tags: ["cooking", "tutorial"], source: "Safari", location: "Downloads", duration: "18:47", dimensions: "1920 × 1080", text: "sourdough starter tutorial bread baking flour water" },
  { id: "vid06", name: "Commute Timelapse.mp4", kind: "Videos", sizeMB: 210, date: "2026-10-10", tags: ["timelapse", "city"], source: "iPhone", location: "Movies", duration: "2:05", dimensions: "1920 × 1080", text: "commute timelapse city traffic morning" },
  { id: "vid07", name: "Ski Trip Run 3.mp4", kind: "Videos", sizeMB: 980, date: "2026-01-24", tags: ["ski", "vacation"], source: "Camera", location: "Movies", duration: "3:58", dimensions: "3840 × 2160", text: "ski run powder mountain winter" },

  // ---- Music (6) ----
  { id: "mus01", name: "Lo-Fi Study Session.mp3", kind: "Music", sizeMB: 58, date: "2026-10-08", tags: ["lo-fi", "focus"], source: "Safari", location: "Music", duration: "42:10", text: "lofi study beats focus music" },
  { id: "mus02", name: "Jazz at Midnight.flac", kind: "Music", sizeMB: 214, date: "2025-12-02", tags: ["jazz"], source: "Music Store", location: "Music", duration: "58:33", text: "jazz midnight saxophone piano trio" },
  { id: "mus03", name: "Podcast — Design Notes Ep 42.mp3", kind: "Music", sizeMB: 84, date: "2026-10-21", tags: ["podcast", "design"], source: "Podcast App", location: "Music", duration: "61:20", text: "design notes podcast interface typography episode forty two" },
  { id: "mus04", name: "Acoustic Demo — Untitled 3.m4a", kind: "Music", sizeMB: 18, date: "2026-08-19", tags: ["demo", "acoustic"], source: "Voice Memos", location: "Music", duration: "3:41", text: "acoustic guitar demo untitled song sketch" },
  { id: "mus05", name: "Vinyl Rip — Kind of Blue Side A.flac", kind: "Music", sizeMB: 302, date: "2025-06-15", tags: ["jazz", "vinyl"], source: "Vinyl Rip", location: "Music", duration: "27:14", text: "kind of blue jazz vinyl miles davis side a" },
  { id: "mus06", name: "Wedding First Dance.mp3", kind: "Music", sizeMB: 9, date: "2024-11-09", tags: ["wedding", "family"], source: "Music Store", location: "Music", duration: "4:02", text: "wedding first dance slow song" },

  // ---- Documents (12) ----
  { id: "doc01", name: "Lease Agreement 2026.pdf", kind: "Documents", sizeMB: 1.2, date: "2026-01-05", tags: ["home", "legal"], source: "Mail", location: "Documents", text: "lease agreement rent deposit landlord tenant 2026" },
  { id: "doc02", name: "Receipt — Apple Store.pdf", kind: "Documents", sizeMB: 0.4, date: "2026-10-23", tags: ["receipt", "purchase"], source: "Mail", location: "Documents", text: "receipt apple store purchase total tax invoice" },
  { id: "doc03", name: "Invoice 1042 — metaPhasic.pdf", kind: "Documents", sizeMB: 0.3, date: "2026-10-16", tags: ["invoice", "work"], source: "Mail", location: "Documents/Projects", text: "invoice 1042 metaphasic consulting payment due" },
  { id: "doc04", name: "Draft — Novel Chapter 12.docx", kind: "Documents", sizeMB: 0.8, date: "2026-10-24", tags: ["draft", "writing"], source: "Local", location: "Documents", text: "draft novel chapter twelve unfinished manuscript notes to finish" },
  { id: "doc05", name: "Draft — Conference Talk Outline.md", kind: "Documents", sizeMB: 0.1, date: "2026-10-13", tags: ["draft", "work"], source: "Local", location: "Documents/Projects", text: "draft conference talk outline unfinished slides TBD placeholder" },
  { id: "doc06", name: "Meeting Notes — Oct 20.md", kind: "Documents", sizeMB: 0.1, date: "2026-10-20", tags: ["work", "notes"], source: "Local", location: "Documents", text: "meeting notes october roadmap decisions action items" },
  { id: "doc07", name: "Passport Scan.pdf", kind: "Documents", sizeMB: 2.4, date: "2025-08-20", tags: ["travel", "identity"], source: "Scanner", location: "Documents", text: "passport scan travel document identification" },
  { id: "doc08", name: "Tax Worksheet 2025.xlsx", kind: "Documents", sizeMB: 0.6, date: "2026-03-30", tags: ["tax", "finance"], source: "Local", location: "Documents", text: "tax worksheet 2025 deductions income spreadsheet" },
  { id: "doc09", name: "Recipe — Tomato Soup.pdf", kind: "Documents", sizeMB: 0.9, date: "2026-02-02", tags: ["cooking", "recipe"], source: "Safari", location: "Documents", text: "recipe tomato soup basil cream cooking instructions" },
  { id: "doc10", name: "Boarding Pass — SFO to LAX.pdf", kind: "Documents", sizeMB: 0.5, date: "2026-10-22", tags: ["travel"], source: "Mail", location: "Downloads", text: "boarding pass sfo lax flight seat gate" },
  { id: "doc11", name: "Research Notes — File Managers.pdf", kind: "Documents", sizeMB: 1.7, date: "2026-10-11", tags: ["research", "work"], source: "Local", location: "Documents/Projects", text: "research notes file managers finder shelves search timeline" },
  { id: "doc12", name: "Receipt — Hardware Store.pdf", kind: "Documents", sizeMB: 0.4, date: "2026-09-28", tags: ["receipt", "home"], source: "Scanner", location: "Documents", text: "receipt hardware store paint brushes total" },

  // ---- Archives (5) ----
  { id: "arc01", name: "Project Backup 2026-09.zip", kind: "Archives", sizeMB: 2100, date: "2026-09-30", tags: ["backup", "work"], source: "Local", location: "Documents/Projects", text: "project backup september archive" },
  { id: "arc02", name: "Old Photos Archive.zip", kind: "Archives", sizeMB: 890, date: "2024-12-19", tags: ["backup", "photos"], source: "Local", location: "Pictures", text: "old photos archive backup family pictures" },
  { id: "arc03", name: "Website Export 2025.tar.gz", kind: "Archives", sizeMB: 145, date: "2025-11-03", tags: ["backup", "web"], source: "Safari", location: "Downloads", text: "website export archive html assets" },
  { id: "arc04", name: "Fonts Collection.zip", kind: "Archives", sizeMB: 68, date: "2026-05-14", tags: ["fonts", "design"], source: "Safari", location: "Downloads", text: "fonts collection typefaces archive" },
  { id: "arc05", name: "Code Repo Snapshot.zip", kind: "Archives", sizeMB: 320, date: "2026-10-18", tags: ["code", "backup"], source: "Local", location: "Documents/Projects", text: "code repo snapshot source archive" },

  // ---- Apps (6) ----
  { id: "app01", name: "Pixel Editor Pro.app", kind: "Apps", sizeMB: 412, date: "2026-07-07", tags: ["design", "editor"], source: "App Store", location: "Applications", text: "pixel editor pro image editing app" },
  { id: "app02", name: "Notes Plus.app", kind: "Apps", sizeMB: 88, date: "2026-09-01", tags: ["notes", "productivity"], source: "App Store", location: "Applications", text: "notes plus productivity app" },
  { id: "app03", name: "Old Video Converter.app", kind: "Apps", sizeMB: 240, date: "2024-05-16", tags: ["video", "old"], source: "Safari", location: "Applications", text: "old video converter app unused" },
  { id: "app04", name: "Task Board.app", kind: "Apps", sizeMB: 120, date: "2026-04-22", tags: ["productivity", "work"], source: "App Store", location: "Applications", text: "task board kanban productivity app" },
  { id: "app05", name: "Photo Cleaner Trial.app", kind: "Apps", sizeMB: 45, date: "2026-10-05", tags: ["trial", "photos"], source: "Safari", location: "Downloads", text: "photo cleaner trial app duplicate photos" },
  { id: "app06", name: "Calculator Plus.app", kind: "Apps", sizeMB: 12, date: "2023-10-30", tags: ["utility"], source: "App Store", location: "Applications", text: "calculator plus utility app" }
];
