# 🔧 Fix for "Multiple commands produce" Build Errors

## Problem
Xcode klager over at flere filer prøver at kopiere til samme destination:
- `Info.plist` 
- `README.md`
- `NotificationService.stringsdata`

## Løsning i Xcode

### 1. Fix README.md fejl

**For hver README.md fil:**

1. Højreklik på filen i Project Navigator
2. Vælg **"Show File Inspector"** (eller tryk ⌘⌥1)
3. I højre sidepanel, under **"Target Membership"**:
   - ✅ Fjern checkmark fra **"AproposMagazinev2"** (main app target)
   - ✅ README.md filer skal IKKE være i nogen target
4. Under **"Copy Bundle Resources"** (hvis synlig):
   - Fjern README.md hvis den er der

**Filer der skal fixes:**
- `README.md` (root)
- `AproposMagazineNotificationService/README.md`

### 2. Fix Info.plist fejl

**For hver Info.plist fil:**

1. Højreklik på `AproposMagazinev2/Info.plist`
2. Show File Inspector (⌘⌥1)
3. Under "Target Membership":
   - ✅ Kun **"AproposMagazinev2"** skal være tjekket af

4. Højreklik på `AproposMagazineNotificationService/Info.plist`
5. Show File Inspector (⌘⌥1)
6. Under "Target Membership":
   - ✅ Kun **"AproposMagazineNotificationService"** skal være tjekket af
   - ❌ Fjern checkmark fra "AproposMagazinev2" hvis den er der

### 3. Fix NotificationService.stringsdata fejl

**For NotificationService.swift:**

1. Højreklik på `AproposMagazineNotificationService/NotificationService.swift`
2. Show File Inspector (⌘⌥1)
3. Under "Target Membership":
   - ✅ Kun **"AproposMagazineNotificationService"** skal være tjekket af
   - ❌ Fjern checkmark fra "AproposMagazinev2" hvis den er der

### 4. Alternativ: Fjern fra Copy Bundle Resources

Hvis filerne stadig er problematiske:

1. Vælg **"AproposMagazinev2"** target i Project Navigator
2. Gå til **"Build Phases"** tab
3. Udvid **"Copy Bundle Resources"**
4. Find og fjern:
   - `README.md`
   - `AproposMagazineNotificationService/README.md`
   - Eventuelle duplikerede Info.plist filer

## Efter Fix

1. **Clean Build Folder**: ⌘⇧K
2. **Build**: ⌘B
3. **Run**: ⌘R

## Noter

- README.md filer er kun dokumentation og skal IKKE være i app bundle
- Hver target skal have sin egen Info.plist
- Extension filer skal kun være i extension target, ikke i main app target
