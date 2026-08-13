trigger EventJourneyGuard on Event (before insert) {
    ActivityJourneyGuardHandler.guardBeforeInsert(Trigger.new);
}