# COPR Makefile for automated php-boringssl builds
# Clones php-boringssl from GitHub, bundles latest BoringSSL, and builds SRPM
#
# COPR calls: make srpm outdir=/path/to/output
#
# BoringSSL is cloned fresh every build to pick up the latest commit.
# The PHP version is tracked via php(zend-abi) / php(api) in the spec,
# so COPR automatically rebuilds when Fedora ships a new PHP.

# COPR provides outdir, set default for local testing
outdir ?= .

# Extension source -- fetch latest from GitHub
EXT_REPO = https://github.com/DigitalCyberSoft/php-boringssl
EXT_VERSION := $(shell curl -sf https://raw.githubusercontent.com/DigitalCyberSoft/php-boringssl/master/php_boringssl.h 2>/dev/null | sed -n '/#define PHP_BORINGSSL_VERSION/{s/.* "//;s/".*//;p}')
ifeq ($(EXT_VERSION),)
EXT_VERSION := 0.1.0
endif

# BoringSSL source
BSSL_REPO = https://boringssl.googlesource.com/boringssl

# Timestamp for snapshot builds
BSSL_DATE := $(shell date -u +%Y%m%d)

# Default target for COPR
srpm:
	@echo "=== Starting php-boringssl SRPM build ==="
	@echo "Output directory: $(outdir)"
	@echo "Extension version: $(EXT_VERSION)"

	# Install SRPM build dependencies
	dnf -y install git rpm-build curl

	# Download php-boringssl source
	@echo "=== Downloading php-boringssl $(EXT_VERSION) ==="
	curl -L -o php-boringssl-$(EXT_VERSION).tar.gz \
		$(EXT_REPO)/archive/refs/tags/v$(EXT_VERSION).tar.gz \
		2>/dev/null || \
	curl -L -o php-boringssl-$(EXT_VERSION).tar.gz \
		$(EXT_REPO)/archive/refs/heads/master.tar.gz
	@echo "  Source tarball ready"

	# Clone BoringSSL (depth=1 for speed, we only need headers + source)
	@echo "=== Cloning latest BoringSSL ==="
	rm -rf boringssl
	git clone --depth=1 $(BSSL_REPO) boringssl
	BSSL_COMMIT=$$(cd boringssl && git rev-parse --short HEAD); \
		echo "  BoringSSL commit: $$BSSL_COMMIT"

	# Create BoringSSL source tarball (exclude .git to save space)
	@echo "=== Packaging BoringSSL source ==="
	tar czf boringssl-$(BSSL_DATE).tar.gz \
		--exclude='.git' \
		--exclude='fuzz' \
		--exclude='third_party/googletest' \
		--exclude='third_party/wycheproof_testvectors' \
		boringssl/
	@echo "  BoringSSL tarball: $$(du -h boringssl-$(BSSL_DATE).tar.gz | cut -f1)"

	# Generate spec file
	@echo "=== Generating spec file ==="
	@( \
	echo '# we dont want -z defs linker flag'; \
	echo '%undefine _strict_symbol_defs_build'; \
	echo ''; \
	echo '%global pecl_name   boringssl'; \
	echo '%global with_zts    0%{!?_without_zts:%{?__ztsphp:1}}'; \
	echo '%global ini_name    40-%{pecl_name}.ini'; \
	echo '%global bssl_date   $(BSSL_DATE)'; \
	echo ''; \
	echo 'Name:           php-%{pecl_name}'; \
	echo 'Version:        $(EXT_VERSION)'; \
	echo 'Release:        1.bssl%{bssl_date}%{?dist}'; \
	echo 'Summary:        BoringSSL TLS extension for PHP'; \
	echo ''; \
	echo 'License:        ISC'; \
	echo 'URL:            $(EXT_REPO)'; \
	echo 'Source0:        php-boringssl-%{version}.tar.gz'; \
	echo 'Source1:        boringssl-%{bssl_date}.tar.gz'; \
	echo ''; \
	echo 'BuildRequires:  gcc'; \
	echo 'BuildRequires:  gcc-c++'; \
	echo 'BuildRequires:  make'; \
	echo 'BuildRequires:  cmake >= 3.12'; \
	echo 'BuildRequires:  ninja-build'; \
	echo 'BuildRequires:  golang'; \
	echo 'BuildRequires:  php-devel >= 8.1'; \
	echo 'BuildRequires:  brotli-devel'; \
	echo 'BuildRequires:  zlib-devel'; \
	echo 'BuildRequires:  libzstd-devel'; \
	echo ''; \
	echo 'Requires:       php(zend-abi) = %{php_zend_api}'; \
	echo 'Requires:       php(api) = %{php_core_api}'; \
	echo ''; \
	echo 'Provides:       bundled(boringssl)'; \
	echo ''; \
	echo '%description'; \
	echo 'PHP extension providing direct access to Google BoringSSL. Exposes'; \
	echo 'BoringSSL-specific TLS features unavailable through ext-openssl: GREASE,'; \
	echo 'extension permutation, certificate compression, ALPS, Encrypted Client'; \
	echo 'Hello (ECH), post-quantum key exchange, TLS fingerprint control, OCSP'; \
	echo 'stapling, SCT, peer certificate inspection, and in-memory cert loading.'; \
	echo ''; \
	echo 'BoringSSL is statically linked into the extension.'; \
	echo ''; \
	echo '%package devel'; \
	echo 'Summary:        Development files for %{name}'; \
	echo 'Requires:       %{name}%{?_isa} = %{version}-%{release}'; \
	echo 'Requires:       php-devel%{?_isa}'; \
	echo ''; \
	echo '%description devel'; \
	echo 'These are the files needed to compile programs using %{name}.'; \
	echo ''; \
	echo '%prep'; \
	echo '%setup -q -n php-boringssl-%{version} -a 1'; \
	echo ''; \
	echo '# Sanity check'; \
	echo 'extver=$$(sed -n '"'"'/#define PHP_BORINGSSL_VERSION/{s/.* "//;s/".*$$//;p}'"'"' php_boringssl.h)'; \
	echo 'if test "x$${extver}" != "x%{version}"; then'; \
	echo '   : Error: Upstream extension version is $${extver}, expecting %{version}.'; \
	echo '   exit 1'; \
	echo 'fi'; \
	echo ''; \
	echo '%if %{with_zts}'; \
	echo 'cp -pr . ../ZTS'; \
	echo '%endif'; \
	echo ''; \
	echo '%build'; \
	echo '# Build BoringSSL from bundled source'; \
	echo 'BSSL_DIR=$$(pwd)/boringssl'; \
	echo 'cd "$$BSSL_DIR"'; \
	echo 'mkdir -p build && cd build'; \
	echo 'cmake -DCMAKE_POSITION_INDEPENDENT_CODE=ON \'; \
	echo '      -DCMAKE_BUILD_TYPE=Release \'; \
	echo '      -GNinja ..'; \
	echo 'ninja -j%{?_smp_build_ncpus:%{_smp_build_ncpus}}%{!?_smp_build_ncpus:$$(nproc)} ssl crypto'; \
	echo 'cd ../../'; \
	echo ''; \
	echo '# NTS build'; \
	echo '%{_bindir}/phpize'; \
	echo '%configure \'; \
	echo '    --with-php-config=%{_bindir}/php-config \'; \
	echo '    --with-libdir=%{_lib} \'; \
	echo '    --with-boringssl="$$BSSL_DIR"'; \
	echo ''; \
	echo 'make %{?_smp_mflags}'; \
	echo ''; \
	echo '%if %{with_zts}'; \
	echo 'cd ../ZTS'; \
	echo 'BSSL_DIR=$$(pwd)/boringssl'; \
	echo 'cd "$$BSSL_DIR" && mkdir -p build && cd build'; \
	echo 'cmake -DCMAKE_POSITION_INDEPENDENT_CODE=ON \'; \
	echo '      -DCMAKE_BUILD_TYPE=Release \'; \
	echo '      -GNinja ..'; \
	echo 'ninja -j%{?_smp_build_ncpus:%{_smp_build_ncpus}}%{!?_smp_build_ncpus:$$(nproc)} ssl crypto'; \
	echo 'cd ../../'; \
	echo '%{_bindir}/zts-phpize'; \
	echo '%configure \'; \
	echo '    --with-php-config=%{_bindir}/zts-php-config \'; \
	echo '    --with-libdir=%{_lib} \'; \
	echo '    --with-boringssl="$$BSSL_DIR"'; \
	echo ''; \
	echo 'make %{?_smp_mflags}'; \
	echo '%endif'; \
	echo ''; \
	echo '%install'; \
	echo 'make install INSTALL_ROOT=%{buildroot}'; \
	echo ''; \
	echo 'install -d %{buildroot}%{php_inidir}'; \
	echo 'cat > %{buildroot}%{php_inidir}/%{ini_name} << EOF'; \
	echo '; Enable BoringSSL extension'; \
	echo 'extension = %{pecl_name}.so'; \
	echo 'EOF'; \
	echo ''; \
	echo '%if %{with_zts}'; \
	echo 'cd ../ZTS'; \
	echo 'make install INSTALL_ROOT=%{buildroot}'; \
	echo 'install -d %{buildroot}%{php_ztsinidir}'; \
	echo 'cp %{buildroot}%{php_inidir}/%{ini_name} \'; \
	echo '   %{buildroot}%{php_ztsinidir}/%{ini_name}'; \
	echo '%else'; \
	echo 'find %{buildroot} -name "%{pecl_name}.so" -not -path "%{buildroot}%{php_extdir}/*" -delete 2>/dev/null || :'; \
	echo '%endif'; \
	echo ''; \
	echo 'install -d %{buildroot}%{php_incldir}/ext/%{pecl_name}'; \
	echo 'cp -p php_boringssl.h %{buildroot}%{php_incldir}/ext/%{pecl_name}/'; \
	echo ''; \
	echo '%check'; \
	echo '%{__php} --no-php-ini \'; \
	echo '    --define extension=%{buildroot}%{php_extdir}/%{pecl_name}.so \'; \
	echo '    --modules | grep "^%{pecl_name}$$"'; \
	echo ''; \
	echo '%{__php} --no-php-ini \'; \
	echo '    --define extension=%{buildroot}%{php_extdir}/%{pecl_name}.so \'; \
	echo '    --ri %{pecl_name} | grep "BoringSSL support"'; \
	echo ''; \
	echo '%if %{with_zts}'; \
	echo '%{__ztsphp} --no-php-ini \'; \
	echo '    --define extension=%{buildroot}%{php_ztsextdir}/%{pecl_name}.so \'; \
	echo '    --modules | grep "^%{pecl_name}$$"'; \
	echo '%endif'; \
	echo ''; \
	echo '%files'; \
	echo '%doc README.md'; \
	echo '%config(noreplace) %{php_inidir}/%{ini_name}'; \
	echo '%{php_extdir}/%{pecl_name}.so'; \
	echo ''; \
	echo '%if %{with_zts}'; \
	echo '%config(noreplace) %{php_ztsinidir}/%{ini_name}'; \
	echo '%{php_ztsextdir}/%{pecl_name}.so'; \
	echo '%endif'; \
	echo ''; \
	echo '%files devel'; \
	echo '%{php_incldir}/ext/%{pecl_name}'; \
	echo ''; \
	echo '%changelog'; \
	echo "* $$(date '+%a %b %d %Y') COPR Builder - $(EXT_VERSION)-1.bssl$(BSSL_DATE)"; \
	echo '- Automated build with latest BoringSSL snapshot'; \
	echo '- BoringSSL statically linked'; \
	) > php-boringssl.spec || exit 1

	@echo "Spec file generated"

	# Build SRPM
	@echo "=== Building SRPM ==="
	rpmbuild -bs \
		--define "_sourcedir $$(pwd)" \
		--define "_specdir $$(pwd)" \
		--define "_builddir $$(pwd)" \
		--define "_srcrpmdir $(outdir)" \
		--define "_rpmdir $$(pwd)" \
		php-boringssl.spec || exit 1

	@echo "=== SRPM build complete ==="
	ls -la $(outdir)/*.src.rpm

clean:
	@rm -f *.tar.gz *.spec *.src.rpm
	@rm -rf boringssl/ php-boringssl-*/

.PHONY: srpm clean
