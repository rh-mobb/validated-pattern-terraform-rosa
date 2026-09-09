<!--
  Do not symlink clusters/README.md here. MkDocs would keep repo-relative
  links (../docs/..., ../modules/...) which 404 on the published site.
  include-markdown rewrites those links relative to this page.
-->
{%
  include-markdown "../../clusters/README.md"
  rewrite-relative-urls=true
%}
