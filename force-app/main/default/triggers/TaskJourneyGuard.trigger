trigger TaskJourneyGuard on Task (before insert) {
    ActivityJourneyGuardHandler.guardBeforeInsert(Trigger.new);
}