<!--
  Do not symlink the module README. include-markdown rewrites repo-relative
  links so they resolve on the published docs site.
-->
{%
  include-markdown "../../modules/infrastructure/route-server/README.md"
  rewrite-relative-urls=true
%}
