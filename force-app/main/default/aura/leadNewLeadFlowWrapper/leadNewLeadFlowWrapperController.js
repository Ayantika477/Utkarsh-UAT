({
    // Finish on the Success/Fault screen: go back to the Lead list view
    handleFinish: function () {
        var navEvt = $A.get('e.force:navigateToObjectHome');
        if (navEvt) {
            navEvt.setParams({ scope: 'Lead' });
            navEvt.fire();
        } else {
            window.top.location.href = '/lightning/o/Lead/list';
        }
    }
})