#!/usr/bin/env python3
"""
Script til at fixe "Multiple commands produce" build errors i Xcode projektet.
Dette script fjerner README.md filer fra Copy Bundle Resources og sikrer korrekt target membership.
"""

import os
import re
import sys
from pathlib import Path

def find_project_file():
    """Find .xcodeproj projekt filen"""
    current_dir = Path.cwd()
    
    # Søg efter .xcodeproj mappe
    for item in current_dir.iterdir():
        if item.is_dir() and item.suffix == '.xcodeproj':
            pbxproj = item / 'project.pbxproj'
            if pbxproj.exists():
                return pbxproj
    
    # Prøv at søge rekursivt
    for item in current_dir.rglob('*.xcodeproj'):
        if item.is_dir():
            pbxproj = item / 'project.pbxproj'
            if pbxproj.exists():
                return pbxproj
    
    return None

def fix_pbxproj(pbxproj_path):
    """Fix projekt filen ved at fjerne README.md fra Copy Bundle Resources"""
    print(f"📖 Læser projekt fil: {pbxproj_path}")
    
    with open(pbxproj_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    original_content = content
    
    # Find alle README.md referencer i Copy Bundle Resources sektioner
    # Vi skal finde PBXResourcesBuildPhase sektioner og fjerne README.md filer
    
    # Pattern til at finde PBXResourcesBuildPhase blokke
    # Vi skal være forsigtige og kun fjerne README.md filer
    
    # Fjern README.md fra Copy Bundle Resources
    # Dette er en simpel tilgang - vi fjerner linjer der indeholder README.md i resources sektioner
    
    # Find alle linjer med README.md i fileRef kontekst
    lines = content.split('\n')
    new_lines = []
    skip_next = False
    
    for i, line in enumerate(lines):
        # Hvis vi ser en README.md fil reference, tjek om den er i en resources sektion
        if 'README.md' in line and 'fileRef' in line:
            # Tjek om vi er i en PBXResourcesBuildPhase sektion
            # Vi skal se bagud for at finde konteksten
            context_start = max(0, i - 50)
            context = '\n'.join(lines[context_start:i+1])
            
            # Hvis vi er i en resources build phase, skip denne linje
            if 'PBXResourcesBuildPhase' in context or '/* Resources */' in context:
                print(f"   ⚠️  Fjerner README.md fra Copy Bundle Resources: {line.strip()}")
                continue
        
        new_lines.append(line)
    
    new_content = '\n'.join(new_lines)
    
    if new_content != original_content:
        # Backup original fil
        backup_path = str(pbxproj_path) + '.backup'
        print(f"💾 Laver backup: {backup_path}")
        with open(backup_path, 'w', encoding='utf-8') as f:
            f.write(original_content)
        
        # Skriv ny fil
        print(f"✏️  Skriver opdateret projekt fil...")
        with open(pbxproj_path, 'w', encoding='utf-8') as f:
            f.write(new_content)
        
        print("✅ Projekt fil opdateret!")
        return True
    else:
        print("ℹ️  Ingen ændringer nødvendige")
        return False

def main():
    print("🔧 Fixer Xcode build errors...")
    print()
    
    pbxproj = find_project_file()
    
    if not pbxproj:
        print("❌ Kunne ikke finde projekt fil (.xcodeproj/project.pbxproj)")
        print()
        print("Manuel løsning:")
        print("1. Åbn projektet i Xcode")
        print("2. Højreklik på README.md filer → Show File Inspector")
        print("3. Fjern checkmark fra 'AproposMagazinev2' target")
        print("4. Gå til Build Phases → Copy Bundle Resources")
        print("5. Fjern README.md filer hvis de er der")
        return 1
    
    try:
        fixed = fix_pbxproj(pbxproj)
        
        if fixed:
            print()
            print("✅ Build errors skulle nu være fixet!")
            print()
            print("Næste skridt:")
            print("1. Åbn projektet i Xcode")
            print("2. Clean Build Folder (⌘⇧K)")
            print("3. Build (⌘B)")
        else:
            print()
            print("⚠️  Projekt filen blev ikke ændret.")
            print("   Dette kan betyde at:")
            print("   - README.md filer allerede er fjernet")
            print("   - Eller de skal fixes manuelt i Xcode")
        
        return 0
        
    except Exception as e:
        print(f"❌ Fejl: {e}")
        return 1

if __name__ == '__main__':
    sys.exit(main())

