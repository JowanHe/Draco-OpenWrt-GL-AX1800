name: build gl.inet

on:
  repository_dispatch:
  workflow_dispatch:

  push:
    paths:
      - '.github/workflows/build-glinet.yml'
      - 'custom.yml'
    branches:
      - master

  schedule:
    - cron: 0 16 * * *

env:
  UPLOAD_FIRMWARE: true
  UPLOAD_WETRANSFER: true
  UPLOAD_RELEASE: true

jobs:
  build:
    runs-on: ubuntu-20.04

    strategy:
      matrix:
        # 设备
        device:
          - target_wlan_ap-gl-ax1800
          - target_wlan_ap-gl-axt1800
          - target_wlan_ap-gl-ax1800-5-4
          - target_wlan_ap-gl-axt1800-5-4
          - target_ipq40xx_gl-a1300
          # - target_mt7981_gl-mt2500
          - target_mt7981_gl-mt3000
          - target_ath79_gl-s200
          # - target_siflower_gl-sf1200
          # - target_siflower_gl-sft1200
          # - target_ramips_gl-mt1300
        # 是否包含官方UI (目前支持IPQ6018系列、mt7981系列、GL-A1300和GL-S200)
        ui:
          - true
          - false
        include:
          - device: target_siflower_gl-sf1200
          - device: target_siflower_gl-sft1200
          - device: target_ramips_gl-mt1300

    steps:
    - name: Checkout
      uses: actions/checkout@main

    - name: Initialization environment
      run: |
        sudo apt update
        sudo apt install python build-essential libncurses5-dev gawk git libssl-dev gettext zlib1g-dev swig unzip time rsync python3 python3-setuptools python3-yaml subversion -y
        git config --global user.name "github-actions[bot]"
        git config --global user.email "github-actions[bot]@github.com"
        chmod 777 ./build.sh

    - name: make
      run: |
        ./build.sh ~ ${{ matrix.device }} ${{ matrix.ui }}

    - name: Organize files
      id: organize
      if: env.UPLOAD_FIRMWARE == 'true' && !cancelled() && !failure()
      run: |
        cd ~/firmware
        echo "FIRMWARE=$PWD" >> $GITHUB_ENV
        cd ~/packages
        echo "PACKAGES=$PWD" >> $GITHUB_ENV
        echo "::set-output name=status::success"

    - name: Upload firmware directory
      uses: actions/upload-artifact@main
      if: steps.organize.outputs.status == 'success' && !cancelled() && !failure()
      with:
        name: OpenWrt_firmware${{ env.DEVICE_NAME }}${{ env.FILE_DATE }}
        path: ${{ env.FIRMWARE }}

    - name: Upload packages directory
      uses: actions/upload-artifact@main
      if: steps.organize.outputs.status == 'success' && !cancelled() && !failure()
      with:
        name: OpenWrt_packages${{ env.DEVICE_NAME }}${{ env.FILE_DATE }}
        path: ${{ env.PACKAGES }}

    - name: Upload firmware to WeTransfer
      id: wetransfer
      if: steps.organize.outputs.status == 'success' && env.UPLOAD_WETRANSFER == 'true' && !cancelled() && !failure()
      run: |
        curl -fsSL git.io/file-transfer | sh
        ./transfer wet -s -p 16 --no-progress ${FIRMWARE} 2>&1 | tee wetransfer.log
        echo "::warning file=wetransfer.com::$(cat wetransfer.log | grep https)"
        echo "::set-output name=url::$(cat wetransfer.log | grep https | cut -f3 -d" ")"

    - name: Generate release tag
      id: tag
      if: true && !failure() && !cancelled()
      run: |
        echo "::set-output name=release_tag::${{ matrix.device }}.${{ matrix.ui }}-$(date +"%Y.%m.%d-%H.%M")"
        touch release.txt
        echo "${{ matrix.device }}" >> release.txt
        [ $UPLOAD_WETRANSFER = true ] && echo "- 🔗 [WeTransfer](${{ steps.wetransfer.outputs.url }})" >> release.txt
        echo -e ${releasePackages} >> release.txt
        echo "::set-output name=status::success"

    - name: Upload firmware to release
      uses: softprops/action-gh-release@v1
      if: steps.tag.outputs.status == 'success' && !cancelled() && !failure()
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      with:
        tag_name: ${{ steps.tag.outputs.release_tag }}
        body_path: release.txt
        files: ${{ env.FIRMWARE }}/*

    - name: Delete workflow runs
      uses: GitRML/delete-workflow-runs@main
      with:
        retain_days: 1
        keep_minimum_runs: 1

    - name: Remove old Releases
      uses: dev-drprasad/delete-older-releases@v0.2.0
      if: env.UPLOAD_RELEASE == 'true' && !cancelled() && !failure()
      with:
        keep_latest: 19
        delete_tags: true
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
