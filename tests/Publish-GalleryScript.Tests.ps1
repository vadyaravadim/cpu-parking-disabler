BeforeAll {
    . (Join-Path $PSScriptRoot '..\.github\Publish-GalleryScript.ps1')
    $script:galleryName = 'cpu-parking-disabler'
    $script:gallery = 'PSGallery'
    $script:releaseVersion = '1.4.0'
    $script:apiKey = 'test-api-key'
    $script:releaseBytes = 'release bytes'
    $script:releaseFile = Join-Path $TestDrive "$galleryName.ps1"
    Set-Content -LiteralPath $releaseFile -Value $releaseBytes -NoNewline
}

Describe 'Publish-GalleryScript' {
    BeforeEach {
        Mock Publish-Script { }
        Mock Save-Script { }
    }

    It 'publishes a version the Gallery does not have' {
        Mock Find-Script { }
        Publish-GalleryScript -Path $releaseFile -Version $releaseVersion -NuGetApiKey $apiKey
        Should -Invoke Find-Script -Times 1 -Exactly -ParameterFilter { $Name -eq $galleryName -and $RequiredVersion -eq $releaseVersion -and $Repository -eq $gallery }
        Should -Invoke Publish-Script -Times 1 -Exactly -ParameterFilter { $Path -eq $releaseFile -and $NuGetApiKey -eq $apiKey -and $Repository -eq $gallery }
        Should -Invoke Save-Script -Times 0 -Exactly
    }

    It 'skips a version the Gallery already has with the same bytes' {
        Mock Find-Script { [pscustomobject]@{ Name = $galleryName; Version = $releaseVersion } }
        Mock Save-Script { Set-Content -LiteralPath (Join-Path $Path "$Name.ps1") -Value $releaseBytes -NoNewline }
        { Publish-GalleryScript -Path $releaseFile -Version $releaseVersion -NuGetApiKey $apiKey } | Should -Not -Throw
        Should -Invoke Save-Script -Times 1 -Exactly -ParameterFilter { $Name -eq $galleryName -and $RequiredVersion -eq $releaseVersion -and $Repository -eq $gallery }
        Should -Invoke Publish-Script -Times 0 -Exactly
    }

    It 'fails on a version the Gallery already has with different bytes' {
        Mock Find-Script { [pscustomobject]@{ Name = $galleryName; Version = $releaseVersion } }
        Mock Save-Script { Set-Content -LiteralPath (Join-Path $Path "$Name.ps1") -Value "$releaseBytes changed" -NoNewline }
        { Publish-GalleryScript -Path $releaseFile -Version $releaseVersion -NuGetApiKey $apiKey } | Should -Throw '*different content*'
        Should -Invoke Publish-Script -Times 0 -Exactly
    }
}
