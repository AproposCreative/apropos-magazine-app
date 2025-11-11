# 📋 Sådan Finder Du Build Settings i Xcode

## Trin-for-trin Guide:

### 1. Vælg Target
- I **øverste del af Xcode** (ved siden af play-knappen), klik på **scheme dropdown**
- Vælg **"AproposMagazineNotificationService"** target

### 2. Åbn Project Settings
- I **venstre side** (Project Navigator), klik på det **blå projekt ikon** øverst
- Dette er projektet "AproposMagazinev2" (det blå ikon)

### 3. Vælg Target
- I **midten af skærmen** (hovedområdet), skal du se **"TARGETS"** sektion
- Klik på **"AproposMagazineNotificationService"** under TARGETS

### 4. Find Build Settings Tab
- I **toppen af midtområdet** skal du se flere tabs:
  - **General** (aktiv)
  - **Signing & Capabilities**
  - **Build Settings** ← **KLIK HER!**
  - **Build Phases**
  - **Build Rules**

### 5. Søg efter Info.plist
- Når du er i **Build Settings** tab:
  - I **søgefeltet øverst** (hvor der står "Filter"), skriv: **"Info.plist"**
  - Eller scroll ned til **"Packaging"** sektion
  - Find **"Info.plist File"** eller **"INFOPLIST_FILE"**

### 6. Tjek Stien
- Under **"Info.plist File"** skal stien være:
  - **`AproposMagazineNotificationService/Info.plist`**
- Hvis den er forkert, **dobbeltklik** på værdien og ret den

## Alternativ Metode:

1. **Vælg projektet** (blå ikon) i venstre side
2. **Vælg target** "AproposMagazineNotificationService" i midten
3. **Klik på "Build Settings"** tab (øverst i midten)
4. **Søg** efter "Info.plist" i søgefeltet

## Visual Guide:

```
Xcode Window:
┌─────────────────────────────────────────┐
│ [Scheme Dropdown ▼] [▶ Play] [⏹ Stop] │ ← Top bar
├─────────────────────────────────────────┤
│ [Project Icon] │ [General] [Build       │
│                │  Settings] [Build     │ ← Tabs her!
│                │  Phases]               │
│                │                        │
│                │  [Søgefelt: Info.plist]│
│                │                        │
│                │  Info.plist File:      │
│                │  AproposMagazine...    │ ← Her!
└─────────────────────────────────────────┘
```

## Hvis Du Ikke Kan Finde Det:

1. **Tryk ⌘1** for at åbne Project Navigator (hvis den ikke er synlig)
2. **Klik på projekt ikonet** (blå) øverst i venstre side
3. **Se i midten** - der skal være tabs øverst
4. **Klik på "Build Settings"** tab

