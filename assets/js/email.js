document.addEventListener("DOMContentLoaded", function () {
  var links = document.querySelectorAll("a.email-link[data-user][data-domain]");
  links.forEach(function (el) {
    var user = el.getAttribute("data-user");
    var domain = el.getAttribute("data-domain");
    if (!user || !domain) return;

    var addr = user + "@" + domain;
    el.textContent = addr;
    el.setAttribute("href", "mailto:" + addr);
    el.setAttribute("rel", "noopener noreferrer");
  });
});
