(function () {
  var toggle = document.getElementById('wyse-nav-toggle');
  var sidebar = document.getElementById('wyse-sidebar');
  if (toggle && sidebar) {
    toggle.addEventListener('click', function () {
      sidebar.classList.toggle('open');
      document.body.classList.toggle('wyse-nav-open');
    });
  }
})();
