# Changelog

## 1.155.0 (165) · stabil dansk/engelsk indlæsning · lokal kandidat · 3. november 2026

- Dansk og engelsk hentes uafhængigt med en afgrænset observationsdeadline. Fejl i ét sprog bevarer gyldigt indhold i det andet; cache/pending og ubrugelige svar kan ikke udgive sig for en frisk tom kilde.
- App og baggrundsopdatering bruger samme eksisterende cachecapture, kold decode og konservative merge. Beholdte gamle rækker forynges ikke; nyere åbne revisioner/body bevares, og rå kildeartikler holdes adskilt fra visningsmerge.
- Egen availability-oprydning fjerner afviste rækker uden at annullere katalogets baseline. Fremmede cachewrites, kontoskift, gamle callbacks og ændringer under adoption afvises fortsat. Fejl følger valgt sprog. Ingen nyt lagringsschema, ekstra service eller retry-løkke.
- 3.648/3.648 hermetiske tests og sourceguard380/0 består; usigneret Release og uafhængigt171-filers pakke-/kildereview består. Fysisk engelsk læser/offlineaccept er fortsat åben. Telefon164 og tidligere accepter bevares; ingen signering, installation, produktion eller ny lyd. AutomationPAUSED; dedikeret iPad udskudt.

## 1.154.0 (164) · meddelelsesåbning, artikelcovers og ulæstmarkør · 3. november 2026

- Artikeltryk fra en notifikation bevares gennem opstartens eksisterende navigation. En præsenteret fuldafspiller kan give plads til artiklen uden at stoppe den aktuelle lyd.
- Artikelbeskeders cover beriges fra den eksisterende godkendte artikelkilde; almindelige tekstbeskeder får ingen billedplads. Modtagne gentagelser uden billedfelt må ikke fjerne et kendt cover. Læst/slettet, dato, sprog, publiceringsgrænser og deduplikering bevares.
- Min side får en diskret ulæstmarkør fra indbakkens faktiske beskeder på det valgte sprog. Ingen separat tæller, ekstra klokke eller automatisk markér-alt-læst.
- Lokal kandidat under verificering; telefon163 og Behemoths fysiske lydaccept bevares. Den ene ejertelefon-test er modtaget, men bannerets artikelåbning fejlede; ingen ny udsendelse, signering eller installation i denne lokale runde. AutomationPAUSED og dedikeret iPad udskudt.

## 1.153.0 (163) · artikelbilledets trykflade · 3. november 2026

- Den fælles PreparedArticleImage afgrænser nu kun sin trykflade til de eksisterende layoutgrænser. Billedets synlige størrelse, beskæring, indlæsning og cache er uændrede; ingen lyd-/rute-/adgangsguards ændres.
- En faktisk indlæst lokal portrætvariant reproducerede en synlig, enabled/hittable lytteknap med koordinattryk0→0; samme brede billedvariant gav0→1. Den samme native prøve bevares til efterkontrol. Det er lokal reproduktion, ikke endnu fysisk Behemoth-accept.
- Telefon162 er installeret;163 er en ny lokal kandidat under kontrol. Ingen ny lyd, serverændring, signering, installation eller testnotifikation følger af denne lokale ændring. AutomationPAUSED og dedikeret iPad udskudt.

## 1.152.0 (162) · afgrænset aflæsning af afspilningsstart · 3. november 2026

- Den aktuelle Behemoth-telefonprøve er stadig uden reaktion. Apples LLDB gik ned før statusaflæsning;161-layoutpakken og dens målinger bevares særskilt.
-162 klargør lukkede startkoder i den eksisterende samtykkestyrede diagnostik. Ingen artikel-/episode-ID, URL, konto, tekst eller rå fejl logges. Startadgang, rute, kilde, konto, lokalfil, sessions- og playerguards bevares; accepted betyder modtaget start, ikke hørbar lyd.
- Den mindre artikelafstand og159/160 bevares. Dette er nødvendig årsagsmåling og ikke en påstået afspilningsreparation. Ingen ny lydproduktion, signing eller installation. Telefon158; godkendt Terminal2-servergenaccept håndteres særskilt af Research. AutomationPAUSED og dedikeret iPad udskudt.

## 1.151.0 (161) · tættere artikelafspilning · 3. november 2026

- Afstanden mellem artiklens lytteknap og hero-billede reduceres fra det ekstra Spacer-led til ét16pt mellemrum. Samme delte body bruges i læseren og native layoutprøven;44pt trykflade og layout uden lytteknap bevares.
- Undersøgelsen af Behemoths døde tryk og Terminallisten2s kildebinding er særskilt; denne layoutændring hævder ikke at reparere afspilningen. Eksisterende optagelser genbruges, ingen ny lyd eller serverændring i161.
-159onboarding og160offlineoprydning bevares. Lokal kandidat under verificering; telefon158. AutomationPAUSED og dedikeret iPad udskudt.

## 1.150.0 (160) · offlineoprydning ved fjernelse · 3. november 2026

- Fælles eksplicit favoritfjernelse rydder artiklens kendte hentede tekst, størrelsesmarkører, offlinebilleder og accepterede lydfil/kvittering. Den præcise gamle tekstkopi fjernes også, så en lokal migration ikke genopretter den.
- Sene tekst-/billed-/lydresultater afvises efter fjernelse. Nyt genvalg og andre lydpins beskyttes af de eksisterende generations-/lease-/evictiongrænser; almindeligt kontoskift, cloudobservation og withdrawal bliver ikke en generel sletning.
- Samme produktfactory kan injiceres med reelle lokale diskadapere til hermetisk kontrol. Ingen ny lagringsmodel, service, dependency eller lydproduktion. Lokal verifikation og senere levering har særskilte kvitteringer; automationPAUSED og dedikeret iPad udskudt bevares.


## 1.149.0 (159) · første onboardingflade · 3. november 2026

- Første velkomst følger ejerens Zalando-reference med Apropos-logo, venstrestillet overskrift, eksisterende blå/hvide grafik og to store login-/opretknapper. Ren sort/hvid baggrund følger systemets udseende; de senere intro-/authflader bevarer deres mørke præsentation.
- Globe-menuen vælger dansk/engelsk gennem samme sprogindstilling som i Indstillinger. Det ændrer ikke introtrin, konto, interessevalg eller nyhedsbrevssamtykke.
- Apple, Google og e-mail ligger bag de nye CTA'er med eksisterende callbacks og account-entry-grænser. Gæstevej, eksisterende konto/replay, interesser og nyhedsbrev bevares. Ingen ny auth-/lagermodel eller provider.
- 159 er en lokal kandidat under verificering; telefon157 og afsluttet/usigneret158-seal bevares. Ingen ny installation, signering, serverændring eller lydproduktion. AutomationPAUSED og dedikeret iPad udskudt.

## 1.148.0 (158) · genvalg af faner · 3. november 2026

- Et nyt tryk på den aktive fane returnerer til dens oversigt fra artikler, kategorier og andre undersider. Samme fælles håndtering gælder Hjem, Artikler, Kategorier og Min side.
- Kun den valgte fanes navigationssti ryddes. Andre faners stakke, søgning, filtre, Min side/Meddelelser og afspilleren genopbygges ikke. Homes eksisterende tilbagevalgs-/scrolladfærd bevares.
- Telefonens fanelinje og den eksisterende sidebjælke bruger samme synkrone SwiftUI-valghåndtering. Den tidligere UIKit-bro monteres ikke; programmatisk navigation er uændret.
- Faktiske før-/efterprøver og begrænsninger dokumenteres i Docs/Reviews/TabReselection-2026-11-03.md.158 er en lokal kandidat; telefonen har157. Ingen ny signering, installation eller serverlevering. AutomationPAUSED og dedikeret iPad udskudt.

## 1.147.0 (157) · lokal kandidat under verificering · 3. november 2026

- Fælles tekststyret billedlayout til lydliste og lydkort samt eksisterende rækker for gemte artikler, kategorier og forfattersider. Billeder følger hele indholdets højde uden at bestemme tekstens højde.
- Titel, metadata, stjerner, billedkilder og særskilte artikel-/afspilningshandlinger bevares. Ingen ny billeddownload, cache, koordinator eller afspilningslogik.
- Den nye native førprøve viser0/2 med faktiske højdeafvigelser ved normal og største tekst. Slutprøver og begrænsninger dokumenteres i Docs/Reviews/AudioRowsSharedArtwork-2026-11-03.md. Behemoths kildebindingskonflikt er et særskilt serverforløb, ikke rettet af billedlayoutet.
- Engelsk156 er separat godkendt til sin præcise tekst-/telefonlevering.157 er ikke signeret eller installeret. AutomationPAUSED og dedikeret iPad udskudt.

## 1.146.0 (156) · lokal kandidat under verificering · 3. november 2026

- Engelsk tekstindlæsning bruger den eksisterende, separate engelske CMS-kilde. Engelsk viser kun publicerede engelske udgaver; dansk katalog, gemninger og cache bevares. Faktisk serverpopulation og offentlig læseadgang kvalificeres særskilt før levering.
- Engelske artikler har ingen lydversion i denne levering. Gemning offline afsluttes med den gemte tekst og venter ikke på lyd eller starter lydgenforsøg. Dansk tekst/lyd beholder sine eksisterende krav.
- Sprogskift rydder en artikelafspilning, som ikke hører til sproget, gennem den eksisterende session. Almindelige, ikke-artikelbundne podcasts og gemte lyttepositioner bevares. Ingen ny oplæsning, lydgenerering eller sletning.
- Telefon155 og tidligere pakker bevares. Denne kandidat er endnu ikke signeret, installeret eller TestFlight-leveret. AutomationPAUSED og dedikeret iPad udskudt.

## 1.145.0 (155) · 3. november 2026

- Min side viser nye gemninger efter faktisk gemmetid med standarden Senest gemt og husker dit valgte sorteringsprincip. Gamle ukendte gemmetidspunkter opfindes ikke.
- Søgeknap og antal reserveres før menulabels ved normal telefontekst. Lange sorteringsnavne sender dem ikke ned på en ny linje. Tilgængelig tekst kan bruge mere plads.
- Allerede indlæste artikelbilleder bruger ingen eksplicit fade-overgang eller ekstra fade-opacity, når visningen genoprettes. Eksisterende cache- og adgangsgrænser bevares.
- Lydknappen afviser ikke den samme optagelse, fordi titel eller cover opdateres. Alle syv medie-/ejer-/kildefelter skal fortsat matche eksakt, og adgang/session genkontrolleres.
- Indbakken bruger tavs første baseline og efterfølgende nye udgivelser. Tvetydige154-originaler arkiveres uden sletning; faktiske modtagelser og læst-/slettevalg bevares. Ulæst badge samordnes via eksisterende appgruppe uden at nulstille ved app-/indbakkeåbning.
- Lokale prøver, fejlstadier og begrænsninger fremgår af Docs/Reviews/OwnerFiveRegressions-2026-11-03.md. Telefonen har154; denne lokale kandidat giver ingen155-signering/installation, ny lydproduktion eller serverændring. Fysisk Behemoth-/offline-/APNsaccept er åben. AutomationPAUSED og dedikeret iPad udskudt.

## 1.144.0 (154) · lokalt testet, usigneret · 2. november 2026

- Meddelelser indhenter artikeludgivelser fra appens friske, godkendte artikelliste, også når push eller lydpublicering fejler. Beskeden åbner artiklen, og den eksisterende rækkevisning og højre cover bevares.
- Stabil artikelidentitet samler gentagelser og bevarer fremtidige læst-/slettet-valg. Første indhentning viser op til de seneste100 publicerede artikler; gamle anonyme slettekvitteringer kan kun knyttes til beskeder, hvis deres artikelmål stadig kendes. Ingen nye pushbeskeder sendes af indhentningen.
- 79/79 berørte og 3549/3549 samlede appprøver består. To hermetiske nativeforløb består med direkte artikelåbning, højre cover, sletning, kold model fra gemte bytes og engelsk ved største tekststørrelse. Faktisk push og fysisk telefonaccept er separate trin.
- App153s rettelse til offlinebrug af eksisterende lyd er bevaret. Research-chatten ejer serverens publicerings-/pushrettelse; ingen serveraktivering, ny lyd eller telefoninstallation følger af denne kandidat.

## 1.143.0 (153) · lokalt verificeret, usigneret · 2. november 2026

- Eksisterende accepterede optagelser kan gemmes sammen med artikelteksten uden ny AI-oplæsning, omkodning eller et nyt bibliotek. Optagelsens identitet holdes adskilt fra tekstens revision.
- MP3 beholder sit filformat; kompatibilitet med tidligere validerede lydreceipts og lagringsgrænser bevares. Konto, medlemskab, sprogområde og tilbagetrækning skal fortsat kvalificeres.
- Rå katalogoptagelser bruger det accepterede artikel-ID gennem kø, lokal filadgang, klargøring og afspilningssession. Ingen gæt ud fra titel og ingen ny optagelse.
- Førprøvens to fejl er bevaret. Slutprøver består 256/256 målrettede og 3523/3523 samlede tests; usigneret iPhoneOS Release består. Tre eksisterende compileradvarsler bevares. Telefonen er fortsat 151; fysisk flytilstandsaccept og installation er separate trin. Se Docs/Reviews/ExistingRecordingOfflineReuse-2026-11-02.md.

## 1.142.0 (152) · lokal kandidat under verificering · 2. november 2026

- Downloadet tekst og valideret lyd gemmes i Application Support, udeladt fra backup. Allerede gemte, præcist kildebundne filer kan genfindes fra den hidtidige cache uden ny hentning; gamle streamingfiler får ikke offlineautoritet.
- Tekstens klarstatus kræver faktisk læsbart, ikke-tomt indhold med samme artikel-/revisionsbinding. Matchende filstørrelse alene er ikke længere tilstrækkelig.
- Konto-/medlemskabsgrænser, downloadprocent, afspilning og eksplicit sletning bevares. Generel serverklargøring, fysisk flytilstand og baggrundsoverførsel er særskilte åbne trin. Telefon151 og tidligere pakker bevares; dedikeret iPad venter, automationPAUSED.

## 1.141.0 (151) · lokal kandidat under verificering · 1. november 2026

- En gemt artikel med tekst, men uden godkendt offline-lyd, viser “Tekst gemt · lyd ikke hentet”. Ventetilstanden vises ikke længere som en mislykket hentning med genforsøg.
- Faktiske hentefejl bevarer genforsøg. Online-lytning, downloadprocent, konto-/kildegrænser og GEMT ved både tekst og valideret lyd er uændrede. Automatisk serverklargøring og fysisk offlineaccept er særskilte åbne trin.
- Telefon150 og alle tidligere forseglede pakker bevares. Dedikeret iPad venter, automationen er PAUSED; ingen ny installation følger af den lokale ændring.

## 1.140.0 (150) · lokal kandidat, usigneret · 1. november 2026

- Artikelpillen følger faktisk bytefremskridt under lydhentning og viser GEMT, når både artikeltekst og valideret lyd er tilgængelig på enheden. Ukendt filstørrelse og manglende lydversion får ingen opdigtet procent.
- Procent er flygtig og bundet til den aktuelle hentning, kilde og adgang; den giver ingen klarstatus eller genforsøg i sig selv. Server-/Research-levering og fysisk offlineaccept er fortsat separate trin. Telefon149 og alle tidligere forseglede pakker bevares; automationPAUSED.

## 1.139.0 (149) · lokal kandidat under udvikling · 1. november 2026

- Automatisk offlinehentning af tekst og godkendt lyd får samlet, ærlig status. Sen katalogaccept, kødræn, afbrud, kold cache og lagringsafslag verificeres i de eksisterende forløb.
- Generel kildekvalificering og afgrænset vedligeholdelse af ældre lyd forberedes mod den eksisterende serverkontrakt; ingen manuel normaldrift pr. episode, ny serveraktivering eller betalt syntese udledes af lokal kode.
- 148-seal, tidligere arbejde, telefon146 og automationPAUSED bevares.149 er ikke signeret, installeret eller accepteret fysisk.

## 1.138.0 (148) · lokal kandidat under verificering · 1. november 2026

- Gemte artiklers ældre metadata kan opdateres under en aktuel, publiceret kilde uden at fjerne/gen-gemme eller omskrive ventende cloudintentioner. Manglende artikeltekst hentes under oprindelige konto-/medlemskabs-/revisionsgrænser i en afgrænset kø.
- Læserens gemmeknap bruger den faktisk viste, afklarede artikel frem for en ældre navigationsværdi.
- Street Fighter er i det frisklæste katalog fortsat streaming-only uden offline-kildebinding. Ingen katalogændring, ny oplæsning eller påstand om offline-lydaccept. 147-seal og EN-serverkandidat bevares; telefon146, automationPAUSED.

## 1.137.0 (147) · lokal kandidat, usigneret ·31. oktober2026

- Gæster får det ejerbestilte login-/kontodesign. Nye gemninger og offlineadgang kræver en konto; én udtrykkelig loginhandling kan færdiggøre den valgte artikel uden at flytte gamle gæstedata.
- Dansk/engelsk brugerflade følger det eksisterende sprogvalg; artikelkatalogerne og CMS-aktivering har særskilte kilde- og servicekrav.
- Hermetisk konto-/gemme- og sprogkontrol samt separate native forløb på iPhone/iPad. Se Docs/Reviews/AccountGateAndInterfaceLanguage-2026-10-31.md for præcise stadier og begrænsninger. Telefon146 og automationPAUSED bevares; engelsk CMS-netværk er fortsat ikke aktiveret.

## 1.128.0 (138) · lokalt verificeret · 30. oktober 2026

- Min sides almindelige ventestatus vises først, hvis den varer mindst600ms. Korte lokale gemmekvitteringer flytter ikke listen med et blinkende statuskort.
- Fejl, genoptagelsesbeskeder og eksplicit åbnet artikelstatus bevarer øjeblikkelig feedback. Gemte valg, journal, kontogrænser og synkronisering ændres ikke.
- Kontrolleret fire-blink-førprøve er rettet til nul blink/listespring.3296units, kvalificerede native/rute-/retryprøver, usigneret Release og uafhængigt review består. Se Docs/Reviews/FavoritesNoticeFlash-2026-10-30.md.
- Lokal kandidat; ingen signering, installation, TestFlight eller genoptaget automation.

## 1.127.0 (137) · lokalt verificeret · 30. oktober 2026

- Klokke ved siden af indstillinger og to vandrette sider under samme overskrift: Min side og Meddelelser.
- 3296/3296 slutunits, native5+5+1,51PNG/42forskellige, usigneret Release og uafhængigt review består. Tidlige AX-/trykfladefund er rettet; sourceguardens tre eksisterende132-fund bevares. Se Docs/Reviews/NotificationInlinePages-2026-10-30.md.
- Artikel- og lydbeskeder åbner direkte gennem eksisterende indholdsrouting. Ingen beskeddetalje, læst-menu, sletning eller synlig ulæst-status.
- Artikelcovers til højre, lokale beskeder, ikonets nulpolitik og eksisterende favoritvalg bevares. Ingen telefon-/TestFlightlevering eller genoptaget automation.

## [1.5] - 2026-05-28

- **Artikel-push virker igen**
  - Fjernet klient-side undertrykkelse af notifikationer når artiklen allerede lå i cache.
- **Push-status i Indstillinger**
  - Viser iOS-tilladelse, FCM-token, tilmeldte emner og knap til Synkroniser push igen.
- **Podcast-notifikationer**
  - Separat toggle for Nye podcasts uafhængigt af artikel-notifikationer.
- **Fortsæt podcast**
  - Banner på forsiden og Fortsæt-knap; afspilning genoptages hvor du slap.
- **Hero-rækkefølge**
  - Nyeste artikler først på forsiden (CMS Created-dato).
- **Hvad er nyt**
  - Viser kun ændringer for den installerede app-version.

## [1.4] - 2026-06-04

- **Bedre artikel-læsning**
  - Afsnit har luft imellem sig, intro-tekst med højere line height, og inline-billeder loader korrekt (WebP + optimerede CMS-størrelser).
- **Billedkreditter**
  - Ophavsret vises som centreret pille under billeder.
- **Log ind i Indstillinger**
  - Google Sign-In med default avatar og "Log ind eller opret en bruger".
- **Forsiden edge-to-edge**
  - Hero-billedet går helt op til toppen uden gap.
- **Notifikations-knap fix**
  - Synlig primær knap i onboarding-sheet i lys og mørk tilstand.

## [1.2] - 2026-05-29

- **Nye podcasts uden app-update**
  - Nye Apropos Podcast-afsnit dukker op i appen automatisk uden ny App Store-version.
- **Besked når ny podcast udkommer**
  - Push-notifikation når et nyt podcast-afsnit er klar.
- **Forbedret podcast-afspiller**
  - Kategori, værter, systemlydstyrke og swipe ned for at lukke.
- **Notifikationer ved første åbning**
  - Velkomst til artikel- og podcast-notifikationer.
- **Hjem virker overalt**
  - Hjem-knappen bringer dig til forsiden fra enhver artikel.
- **Hurtigere artikler**
  - Hurtigere åbning af artikler og mere responsiv forside.

## [Unreleased] - 2025-01-XX

### 🔔 Notification System Improvements

#### Backend (Cloud Run / Firebase Functions)
- **Fixed duplicate notifications for republished articles**
  - Implemented Firestore-based tracking system (`notified_articles` collection)
  - Articles are now tracked when first published, preventing duplicate notifications on republish
  - Added comprehensive logging for debugging notification flow
  - Added validation to block notifications if `article_id` is empty
  - Changed error handling: if Firestore check fails, notification is blocked (safer than sending duplicates)

- **Fixed missing article_id in notification payload**
  - Corrected Webflow webhook payload parsing to extract `article_id` from `webhookData.payload.items[0].id`
  - Added `thumbnail_url` and `cover_url` to notification payload for rich notifications
  - Added `mutable-content: 1` flag to APNS payload to enable Notification Service Extension

- **Improved webhook trigger filtering**
  - Only sends notifications for `collection_item_published` or `publish` triggers
  - Ignores `collection_item_changed` and `collection_item_created` triggers

#### iOS App
- **Notification Service Extension**
  - Implemented duplicate notification check using cached articles
  - If article exists in cache (App Group or standard UserDefaults), notification is blocked
  - Added fallback to find article by name if `article_id` is missing
  - Added rich notification support with thumbnail images
  - Fixed App Groups capability configuration for data sharing between app and extension

- **AppDelegate notification handling**
  - Added duplicate check in `willPresent` for foreground notifications
  - Simplified logic: if article exists in cache, it's considered already published
  - Improved logging for debugging

- **Cache Manager**
  - Updated to save simplified article data to App Group UserDefaults
  - Enables Notification Service Extension to access cached articles for duplicate checks

### 🎨 What's New Feature

- **Fixed What's New display timing**
  - Consolidated duplicate `.onAppear` modifiers
  - Added 0.5 second delay to ensure ContentView is fully visible before showing sheet
  - Improved logging for debugging
  - Updated to mark all entries as seen when dismissed (prevents re-showing)

- **What's New Manager**
  - Automatically shows latest version if not seen before
  - Compares versions semantically (e.g., 2.3.0 > 2.2.0)
  - Supports multiple entries in `whatsnew.json`
  - Stores last seen version in UserDefaults

### 🧹 Code Cleanup

- **Removed verbose logging**
  - Reduced console spam from various services
  - Kept essential logging for debugging
  - Removed unnecessary print statements

- **Removed guide files**
  - Deleted temporary guide files (`FIX_INDEX_JS.txt`, `QUICK_FIX_GUIDE.md`, `IMPLEMENTATION_GUIDE.md`)
  - Cleaned up project structure

### 🐛 Bug Fixes

- **Fixed NavigationCoordinator deallocation**
  - Converted to singleton pattern to ensure persistent instance
  - Fixed `nil` NavigationCoordinator in notification observers

- **Fixed Firestore persistence configuration**
  - Moved `configurePersistenceIfNeeded()` to `AppDelegate.didFinishLaunchingWithOptions()`
  - Added static flag to prevent multiple configurations
  - Fixed `FIRIllegalStateException` crash

- **Fixed console spam**
  - Removed excessive logging from SwipeBack, SplashView, and other components
  - Cleaned up debug messages

### 📝 Documentation

- Added comprehensive changelog documenting all recent changes
- Improved code comments for notification system
- Added logging for debugging What's New feature

---

## Technical Details

### Notification Flow

1. **Webflow publishes article** → Webhook sent to Cloud Run service
2. **Backend checks Firestore** → If article exists in `notified_articles`, block notification
3. **If new article** → Mark as notified in Firestore, send FCM notification
4. **iOS receives notification** → Notification Service Extension checks cache
5. **If article in cache** → Block notification (already published)
6. **If new article** → Show notification with thumbnail

### What's New Flow

1. **App launches** → ContentView appears
2. **After 0.5 second delay** → Check if What's New should be shown
3. **Compare current version** with last seen version
4. **If newer version** → Show What's New sheet
5. **When dismissed** → Mark all entries as seen

### Files Modified

#### Backend
- `functions/index.js` - Webflow webhook handler with Firestore tracking

#### iOS App
- `AppDelegate.swift` - Notification handling and duplicate checks
- `AproposMagazineNotificationService/NotificationService.swift` - Notification Service Extension
- `Services/CacheManager.swift` - App Group cache support
- `ContentView.swift` - What's New display logic
- `Managers/WhatsNewManager.swift` - What's New version management
- `Models/NavigationCoordinator.swift` - Singleton pattern implementation
- Various services - Reduced verbose logging

---

## Migration Notes

### For Developers

1. **Backend Deployment**: Deploy `functions/index.js` with Firebase Functions
2. **Firestore Setup**: Ensure `notified_articles` collection has proper permissions
3. **App Groups**: Verify both app and extension have `group.com.aproposmagazine.app` capability
4. **What's New**: Update `Resources/WhatsNew/whatsnew.json` with new version entries

### For Users

- No action required
- What's New will automatically appear for new app versions
- Notifications will only appear for truly new articles (not republished ones)

