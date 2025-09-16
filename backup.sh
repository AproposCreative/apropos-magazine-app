#!/bin/bash

# Apropos Magazine - Automatisk Backup Script
# Dette script sikrer at alle ændringer automatisk bliver committet og pushed til GitHub

# Farver for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Projekt sti
PROJECT_DIR="/Users/frederikkragh/Library/CloudStorage/Dropbox/AproposMagazine.com/07. iOS App - Apropos Magazine"

echo -e "${BLUE}🔄 Starter automatisk backup af Apropos Magazine projekt...${NC}"

# Gå til projekt mappen
cd "$PROJECT_DIR" || {
    echo -e "${RED}❌ Fejl: Kunne ikke finde projekt mappen: $PROJECT_DIR${NC}"
    exit 1
}

# Tjek Git status
echo -e "${YELLOW}📊 Tjekker Git status...${NC}"
git status --porcelain > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Fejl: Dette er ikke et Git repository${NC}"
    exit 1
fi

# Tjek om der er ændringer
if [ -z "$(git status --porcelain)" ]; then
    echo -e "${GREEN}✅ Ingen ændringer at committe${NC}"
    exit 0
fi

# Vis ændringer
echo -e "${YELLOW}📝 Følgende ændringer blev fundet:${NC}"
git status --short

# Tilføj alle ændringer
echo -e "${YELLOW}➕ Tilføjer alle ændringer...${NC}"
git add .

# Opret commit med timestamp
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
COMMIT_MESSAGE="Automatisk backup - $TIMESTAMP

- Automatisk commit af alle ændringer
- Backup oprettet: $(date)"

# Commit ændringer
echo -e "${YELLOW}💾 Committer ændringer...${NC}"
git commit -m "$COMMIT_MESSAGE"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Commit oprettet succesfuldt${NC}"
else
    echo -e "${RED}❌ Fejl ved oprettelse af commit${NC}"
    exit 1
fi

# Push til GitHub
echo -e "${YELLOW}🚀 Pusher til GitHub...${NC}"
git push origin main

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Backup fuldført succesfuldt!${NC}"
    echo -e "${GREEN}📅 Backup oprettet: $TIMESTAMP${NC}"
    echo -e "${GREEN}🔗 Repository: https://github.com/AproposCreative/apropos-magazine-app${NC}"
else
    echo -e "${RED}❌ Fejl ved push til GitHub${NC}"
    echo -e "${YELLOW}💡 Prøv at køre: git push origin main manuelt${NC}"
    exit 1
fi

echo -e "${BLUE}🎉 Automatisk backup fuldført!${NC}"
