// The touch controls' cheat (sithewok): what the app does for it. See
// IOSCheatGame.h; the cheat itself is in the player entity (IOSCheat.h).

#include "SeriousSam/StdH.h"
#include "SeriousSam/LevelInfo.h"
#include <Engine/Templates/Stock_CSoundData.h>
#include "IOSCheatGame.h"

// this phone's player in the game being played (NULL: none)
static CPlayer *IOSCheatGame_LocalPlayer(void)
{
  if (!_pGame->gm_bGameOn) return NULL;
  for (INDEX i=0; i<CEntity::GetMaxPlayers(); i++) {
    CEntity *pen = CEntity::GetPlayerEntity(i);
    if (pen!=NULL && _pNetwork->IsPlayerLocal(pen)) return (CPlayer *)pen;
  }
  return NULL;
}

extern "C" int IOSCheatGame_Allowed(void)
{
  if (!_pGame->gm_bGameOn) return 0;
  if (_gmRunningGameMode!=GM_SINGLE_PLAYER && _gmRunningGameMode!=GM_NETWORK) return 0;
  const CSessionProperties *psp = (const CSessionProperties *)_pNetwork->GetSessionProperties();
  return psp->sp_ctMaxPlayers==1 || psp->sp_bQuickTest || psp->sp_bIOSAllowCheats;
}

// ---------------------------------------------------------------- levels

// The campaign's levels: single-player levels whose names start with their
// number (The First Encounter's "01_Hatshepsut", The Second Encounter's
// "1_1_Palenque"), in the order of their file names, as the game lists them
static CStaticStackArray<CTFileName> _afnmLevels;
static BOOL _bLevelsListed = FALSE;

static void IOSCheatGame_ListLevels(void)
{
  if (_bLevelsListed) return;
  _bLevelsListed = TRUE;
  FOREACHINLIST(CLevelInfo, li_lnNode, _lhAllLevels, itli) {
    const CLevelInfo &li = *itli;
    const CTString strName = li.li_fnLevel.FileName();
    if (!(li.li_ulSpawnFlags&SPF_SINGLEPLAYER) || !isdigit((unsigned char)((const char *)strName)[0])) continue;
    _afnmLevels.Push() = li.li_fnLevel;
  }
}

extern "C" int IOSCheatGame_NumLevels(void)
{
  if (_gmRunningGameMode!=GM_SINGLE_PLAYER) return 0;
  IOSCheatGame_ListLevels();
  return _afnmLevels.Count();
}

extern "C" int IOSCheatGame_GoToLevel(int iLevel)
{
  if (_gmRunningGameMode!=GM_SINGLE_PLAYER || iLevel<1 || iLevel>IOSCheatGame_NumLevels()) return 0;
  const CTFileName fnmLevel = _afnmLevels[iLevel-1];
  // a new single-player game there, at the difficulty of this one
  const CSessionProperties *pspNow = (const CSessionProperties *)_pNetwork->GetSessionProperties();
  // (Mental is Hard plus sp_bMental; the menu's number for it is 4)
  _pShell->SetINDEX("gam_iStartDifficulty", pspNow->sp_bMental ? (INDEX)4 : (INDEX)pspNow->sp_gdGameDifficulty);
  _pShell->SetINDEX("gam_iStartMode", CSessionProperties::GM_COOPERATIVE);
  _pGame->gm_StartSplitScreenCfg = CGame::SSC_PLAY1;
  _pGame->gm_aiStartLocalPlayers[0] = _pGame->gm_iSinglePlayer;
  _pGame->gm_aiStartLocalPlayers[1] = -1;
  _pGame->gm_aiStartLocalPlayers[2] = -1;
  _pGame->gm_aiStartLocalPlayers[3] = -1;
  _pGame->gm_strNetworkProvider = "Local";
  CUniversalSessionProperties sp;
  _pGame->SetSinglePlayerSession(sp);
  CPrintF("sithewok: level %d, %s\n", iLevel, (const char *)fnmLevel);
  if (_pGame->NewGame(fnmLevel.FileName(), fnmLevel, sp)) {
    _gmRunningGameMode = GM_SINGLE_PLAYER;
    return 1;
  }
  _gmRunningGameMode = GM_NONE;
  return 0;
}

// ---------------------------------------------------------------- the sound

// Sam's lines, from the game's own files (never in the app)
#ifdef FIRST_ENCOUNTER
static const char *const _astrLines[] = {
  "Sounds\\Player\\Quotes\\Lets_get_serious.wav",
  "Sounds\\Player\\Quotes\\lets_rock_and_roll.wav",
  "Sounds\\Player\\Quotes\\Serious_firepower.wav",
  "Sounds\\Player\\Quotes\\ready_for_battle.wav",
};
#else
static const char *const _astrLines[] = {
  "Sounds\\Player\\Quotes\\Sam_i_am.wav",
  "Sounds\\Player\\Quotes\\Yeehaw!!!.wav",
};
#endif
#define IOSCHEATGAME_LINES (INDEX)(sizeof(_astrLines)/sizeof(_astrLines[0]))

extern "C" void IOSCheatGame_PlaySound(void)
{
  static CSoundObject *pso = NULL;
  static CSoundData *apsd[IOSCHEATGAME_LINES];
  static INDEX iLast = -1;
  if (pso==NULL) {
    pso = new CSoundObject;
    for (INDEX i=0; i<IOSCHEATGAME_LINES; i++) {
      apsd[i] = NULL;
      try {
        apsd[i] = _pSoundStock->Obtain_t(CTString(_astrLines[i]));
      } catch (const char *strError) {
        CPrintF("sithewok: %s\n", strError);
      }
    }
  }
  // a different line from last time (any, if only one can be played)
  INDEX ctOk = 0;
  INDEX aiOk[IOSCHEATGAME_LINES];
  for (INDEX i=0; i<IOSCHEATGAME_LINES; i++) {
    if (apsd[i]!=NULL && i!=iLast) aiOk[ctOk++] = i;
  }
  if (ctOk==0 && iLast>=0 && apsd[iLast]!=NULL) aiOk[ctOk++] = iLast;
  if (ctOk==0) return;
  iLast = aiOk[rand()%ctOk];
  // (not a game sound: it plays whether or not the game is paused, at the
  // sound effects volume as every sound does)
  pso->Play(apsd[iLast], SOF_NONGAME);
}

// ---------------------------------------------------------------- falls

extern "C" unsigned int IOSCheatGame_Catches(void)
{
  CPlayer *pl = IOSCheatGame_LocalPlayer();
  return pl!=NULL ? (unsigned int)pl->m_ctIOSCatches : 0;
}

extern "C" unsigned int IOSCheatGame_World(void)
{
  // (a new player, or the game's time gone back: a game loaded, maybe of
  // the same level, its player where the last one was in memory)
  static unsigned int uWorld = 1;
  static CPlayer *plLast = NULL;
  static TIME tmLast = 0.0f;
  CPlayer *pl = IOSCheatGame_LocalPlayer();
  const TIME tmNow = (pl!=NULL) ? _pNetwork->GetGameTime() : 0.0f;
  // (and a new level's file: a level changed, its player copied over)
  static CTString strLast;
  const CTString strNow = (pl!=NULL) ? CTString(_pNetwork->ga_World.wo_fnmFileName) : CTString("");
  if (pl!=plLast || (pl!=NULL && (tmNow<tmLast || strNow!=strLast))) {
    plLast = pl;
    if (pl!=NULL) uWorld++;
  }
  tmLast = tmNow;
  strLast = strNow;
  return uWorld;
}
