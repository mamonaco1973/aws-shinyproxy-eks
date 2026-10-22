// Copies the visible credentials into the hidden form and submits it.
//
// The visible form posts to javascript:void and never submits on its own.
// Keeping the password input out of any form with a real action is what
// stops ISP phishing filters from classifying this page as credential
// harvesting - see the comment at the top of login.html.
function submitRealForm() {
  document.getElementById("realusername").value =
    document.getElementById("username").value;
  document.getElementById("realpassword").value =
    document.getElementById("password").value;
  document.forms["realform"].submit();
}

// After the title bar's Sign out (see fragments/navbar.html), say so once.
document.addEventListener("DOMContentLoaded", function () {
  try {
    if (sessionStorage.getItem("vs-signed-out")) {
      sessionStorage.removeItem("vs-signed-out");
      document.getElementById("signedout").hidden = false;
    }
  } catch (e) {
    // Storage blocked (private mode, policy): skip the notice.
  }
});
