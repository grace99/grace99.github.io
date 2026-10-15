// Browser-visible configuration. Never put a service_role or sb_secret key here.
window.FERNSVILLA_SUPABASE = {
  signupRedirect: 'https://grace99.github.io/?signup=confirmed',
  passwordResetRedirect: 'https://grace99.github.io/?reset-password=1',
  url: 'https://exrhpaqpepubscyqflov.supabase.co',
  publishableKey: 'sb_publishable_ci3CPqZv5I-AcANDCSxh5g_OqBepLsm',
  villaMaster: {
    table: 'villaMaster',
    columns: {
      key: 'Villa', id: 'Villa', name: 'Name', type: 'OwnORrent', due: 'MaintAmount',
      phone: 'PriPhoneNo', area: 'Area', street: 'Street', resStatus: 'ResStatus',
      numRes: 'NumRes', numKids: 'NumKids', numVehicles: 'NumVehicles', numPets: 'NumPets',
      ownCCTV: 'OwnCCTV', ownPwrLine: 'OwnPwrLine', oStatus: 'Ostatus',
      secPhone: 'SecPhoneNo', priEmail: 'PriEmailAdd', secEmail: 'SecEmailAdd'
    }
  }
};
