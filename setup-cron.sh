#!/bin/bash

# Setup script for automatisk backup med cron
# Dette script sætter op en cron job der kører backup hver time

# Farver for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PROJECT_DIR="/Users/frederikkragh/Library/CloudStorage/Dropbox/AproposMagazine.com/07. iOS App - Apropos Magazine"
BACKUP_SCRIPT="$PROJECT_DIR/backup.sh"

echo -e "${BLUE}🔧 Sætter op automatisk backup med cron...${NC}"

# Tjek om backup script eksisterer
if [ ! -f "$BACKUP_SCRIPT" ]; then
    echo -e "${RED}❌ Fejl: Backup script ikke fundet: $BACKUP_SCRIPT${NC}"
    exit 1
fi

# Gør backup script eksekverbart
chmod +x "$BACKUP_SCRIPT"
echo -e "${GREEN}✅ Backup script gjort eksekverbart${NC}"

# Opret cron job (kør hver time)
CRON_JOB="0 * * * * $BACKUP_SCRIPT >> $PROJECT_DIR/backup.log 2>&1"

# Tjek om cron job allerede eksisterer
if crontab -l 2>/dev/null | grep -q "$BACKUP_SCRIPT"; then
    echo -e "${YELLOW}⚠️ Cron job eksisterer allerede${NC}"
    echo -e "${YELLOW}📋 Nuværende cron jobs:${NC}"
    crontab -l | grep "$BACKUP_SCRIPT"
else
    # Tilføj cron job
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo -e "${GREEN}✅ Cron job tilføjet succesfuldt${NC}"
    echo -e "${GREEN}⏰ Backup kører nu hver time${NC}"
fi

echo -e "${BLUE}📋 Nuværende cron jobs:${NC}"
crontab -l

echo -e "${GREEN}🎉 Automatisk backup setup fuldført!${NC}"
echo -e "${YELLOW}💡 Tips:${NC}"
echo -e "   - Backup kører hver time"
echo -e "   - Log fil: $PROJECT_DIR/backup.log"
echo -e "   - Manuelt backup: $BACKUP_SCRIPT"
echo -e "   - Fjern cron job: crontab -e (slet linjen med backup.sh)"
