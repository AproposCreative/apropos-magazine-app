#!/bin/bash

# Script til at fixe Xcode build errors ved at manipulere projekt filen
# Dette script skal køres fra projekt root mappen

set -e

echo "🔧 Fixer Xcode build errors..."
echo ""

# Find projekt fil
PROJECT_FILE=$(find . -name "project.pbxproj" -type f | head -1)

if [ -z "$PROJECT_FILE" ]; then
    echo "❌ Kunne ikke finde project.pbxproj fil"
    echo ""
    echo "💡 Manuel løsning i Xcode:"
    echo ""
    echo "1. Åbn projektet i Xcode"
    echo "2. For hver README.md fil:"
    echo "   - Højreklik → Show File Inspector (⌘⌥1)"
    echo "   - Under 'Target Membership': Fjern checkmark fra 'AproposMagazinev2'"
    echo ""
    echo "3. For AproposMagazineNotificationService/NotificationService.swift:"
    echo "   - Højreklik → Show File Inspector"
    echo "   - Under 'Target Membership': Kun 'AproposMagazineNotificationService' skal være tjekket"
    echo ""
    echo "4. For Info.plist filer:"
    echo "   - Hver Info.plist skal kun være i sit eget target"
    echo ""
    echo "5. Build Phases → Copy Bundle Resources:"
    echo "   - Fjern README.md filer hvis de er der"
    echo ""
    exit 1
fi

echo "📖 Fundet projekt fil: $PROJECT_FILE"
echo ""

# Lav backup
BACKUP_FILE="${PROJECT_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
cp "$PROJECT_FILE" "$BACKUP_FILE"
echo "💾 Backup oprettet: $BACKUP_FILE"
echo ""

# Tjek om vi kan læse filen
if [ ! -r "$PROJECT_FILE" ]; then
    echo "❌ Kan ikke læse projekt fil"
    exit 1
fi

echo "⚠️  Dette script kan ikke automatisk fixe alle problemer"
echo "   Projekt filen er kompleks og kræver manuel redigering i Xcode"
echo ""
echo "📋 Følg disse trin i Xcode:"
echo ""
echo "1. Åbn projektet i Xcode"
echo ""
echo "2. Fix README.md filer:"
echo "   - Højreklik på README.md (root) → Show File Inspector (⌘⌥1)"
echo "   - Under 'Target Membership': Fjern checkmark fra 'AproposMagazinev2'"
echo "   - Gentag for AproposMagazineNotificationService/README.md"
echo ""
echo "3. Fix NotificationService.swift:"
echo "   - Højreklik på AproposMagazineNotificationService/NotificationService.swift"
echo "   - Show File Inspector → Target Membership"
echo "   - Kun 'AproposMagazineNotificationService' skal være tjekket"
echo ""
echo "4. Fix Info.plist filer:"
echo "   - AproposMagazinev2/Info.plist → Kun 'AproposMagazinev2' target"
echo "   - AproposMagazineNotificationService/Info.plist → Kun extension target"
echo ""
echo "5. Build Phases → Copy Bundle Resources:"
echo "   - Vælg 'AproposMagazinev2' target"
echo "   - Gå til 'Build Phases' tab"
echo "   - Udvid 'Copy Bundle Resources'"
echo "   - Fjern README.md filer hvis de er der"
echo ""
echo "6. Efter fix:"
echo "   - Clean Build Folder (⌘⇧K)"
echo "   - Build (⌘B)"
echo ""

exit 0

