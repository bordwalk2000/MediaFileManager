<#
.SYNOPSIS
Renames TV Show files to a specific naming scheme and moves the files to their correct seasons folder.

.DESCRIPTION
The script calls The Movie Database, themoviedb.org API to fetch information about the TV Shows, Seasons,
and Episodes.

It takes that data and creates Season folders for every season; Renames the TV Shows episodes to the
correct specified scheme normally "[TV Show Name] [Season & Episode Number] [Episode Name]".
Then moves the episodes into the correct season folder.

After the script has finished processing the files, empty folders are removed.

.PARAMETER FolderPath
Specify the path to the TV Show folder where you want the files to be processed.

.PARAMETER TheMovieDB_API
Will need to have a themoviedb.org account setup to get a free API token. This is what allows the API
calls to be authenticated to return data.

.PARAMETER TVShowID
If the search is not returning the correct TV Show or you just want to manually specify one, you grab it
off themoviedb.org website and the script will use that ID when pulling information about the TV Show.

.PARAMETER Separator
Allows specifying the separator that is used when separating Season and Episode numbers. Example S01.E02

Allows the following characters to be used as a separator 'xX.-_ ' and a one character limit.

Defaults to use the period if nothing is defined.

.PARAMETER NoSeparator
Will cause the script to not use a separator between Season and Episode numbers.  Example S01E02

Will override anything defined in the -Separator parameter.

.INPUTS
None. You cannot pipe objects to format-tvshows.ps1.

.OUTPUTS
None. format-tvshows.ps1 does not generate any output.

.EXAMPLE
Format-TVShow -FolderPath 'Friends -TheMovieDB_API $env:moviedbapi -Separator "x"

Basic example specify a specific separator.

.NOTES
Author: Bradley Herbst
Created: February 10th, 2017

PROBLEMS: Doesn't currently handle processing two Episodes in one File.
It will rename the file to the first episode and you will need to manually fix
the name and specify the second episode.
#>
Function Format-TVShow {
    [CmdletBinding()]
    # Ignore VSCode warning saying that $count is not being used, because it's defined in the begin scope.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseDeclaredVarsMoreThanAssignments',
        'count',
        Justification = 'variable is used in another scope'
    )]
    param (
        [Parameter(
            Mandatory
        )]
        [ValidateNotNullOrEmpty()]
        [IO.DirectoryInfo]
        $FolderPath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $TheMovieDB_API,

        [Parameter()]
        [string]
        $TVShowID,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('[xX\.\-_ ]')]
        [ValidateLength(1, 1)]
        [string]
        $Separator = ".",

        [Parameter()]
        [switch]
        $NoSeparator,

        [Parameter()]
        [string]
        $BaseURL = "https://api.themoviedb.org/3"
    )

    begin {
        # System Check for Invalid Filename Characters
        $InvalidFileNameChars = [string]::join('*',
            ([IO.Path]::GetInvalidFileNameChars())
        ) -replace '\\', '\\'
    }

    process {
        # Verify Folder Path is Valid
        if (-not (Test-Path $FolderPath)) {
            Write-Error 'Folder Path File Not Valid' -ErrorAction Stop
        }

        # Check if Able to Successfully Call TheMovieDB API
        try {
            Write-Verbose "Test API Connection"
            Write-Debug $(Invoke-RestMethod -Uri "$BaseURL/genre/movie/list?api_key=$TheMovieDB_API")
        }
        catch {
            $StatusCode = $_.Exception.Response.StatusCode
            Write-Debug API StatusCode: $StatusCode
            if ($StatusCode -eq 401) {
                $ErrorMessage = "Error Code: 401 Unauthorized. Unable to Connect to API. `n$_"
                Write-Error $ErrorMessage -ErrorAction Stop
            }
            else {
                $ErrorMessage = "Expected 200, got $([int]$StatusCode) Unable to Connect to API. `n$_"
                Write-Error $ErrorMessage -ErrorAction Stop
            }
        }

        # Find TheMovieDB TV Show ID if Not Specified
        if (!$TVShowID) {
            #Grab TV Show Name From Folder Name
            $FolderName = Split-Path $FolderPath -leaf

            # Check For Year Tag and Get Value Ready for Search Query if Found
            if ($FolderName -match '\s\(\d{4}\)') {
                $YearSearch = $FolderName -match '\s\(\d{4}\)' | Select-Object -First 1
                | ForEach-Object {
                    # Returns Section of the String that the Regex Validated
                    $Matches.Values -Replace '[^\d]'
                }
            }

            # Combine TV Show Name with Search Year Criteria
            $SearchString = $FolderName -replace '\s\(\d{4}\)', ''

            # Splat Parameters Used for Find-TheMovieDBTVShow Function
            $Params = @{
                APIKey       = $TheMovieDB_API
                SearchString = $SearchString
                BaseURL      = $BaseURL
            }

            # Add YearSearch if one was found.
            if ($YearSearch) { $Params.Year = $YearSearch }

            # Call Get API to get TV Show ID
            $Results = Find-TheMovieDBTVShow @Params

            # Verify Results were Returned
            if ($Results.count -lt 1) {
                $ErrorMessage = "Unable to find results based on tv show search query: $SearchString`r`n" +
                "Either update folder name or supply TheMovieDB TV Show ID."
                Write-Error $ErrorMessage -ErrorAction Stop
            }

            # Populate TVShowID Variable
            $TVShowID = $Results.ID
            Write-Verbose "TV Show TheMovieDB ID: $TVShowID"
        }

        # Get TV Show Information
        $TVShowInfo = Get-TheMovieDBTVShowInfo -TVShowID $TVShowID -APIKey $TheMovieDB_API -BaseURL $BaseURL

        # Move 'The/A/An' to the End of the Title
        $FormattedTVShowName = $TVShowInfo.name -replace '^(the|a|an) (.*)$', '$2, $1'

        # Remove Colon from the Name; Not a Supported Filename Character on Windows
        $FormattedTVShowName = $FormattedTVShowName -Replace (': ', ' - ')

        # Replace Open Parentheses with Dash
        $FormattedTVShowName = $FormattedTVShowName -Replace (' \(', ' - ')

        # Remove Special Characters Not Supported On Different Operating Systems As Valid Filename Characters.
        $FormattedTVShowName = $FormattedTVShowName -Replace '[?(){}]'

        # Remove Colon from the Name; Not a Supported Windows Filename Character.
        $FormattedTVShowName = $FormattedTVShowName -replace "[$InvalidFileNameChars]", ''

        # Replace any Multiple Spaces with a Single Space
        $FormattedTVShowName = $FormattedTVShowName -Replace ('\s+', ' ')

        # Grab Only the Year from the First Aired Date
        $FirstAiredYear = $TVShowInfo.first_air_date.Split('-')[0]

        # Put TV Show Folder Name String Together.
        $TVShowFolderName = "$($FormattedTVShowName) ($FirstAiredYear)"
        Write-Debug "TV Show Folder Name: $TVShowFolderName"

        # Define Variable for Path to Newly Named Folder
        $UpdatedFolderPath = (
            Join-Path -Path (Split-Path -Path $FolderPath -Parent
            ) -ChildPath $TVShowFolderName)

        # Checks Folder Name is Different From New Name
        if ($(Split-Path -Path $FolderPath -Leaf) -ne $TVShowFolderName) {
            # Verify New Name Folder Doesn't Already Exists
            if (-not (Test-Path $UpdatedFolderPath)) {
                # Rename TV Show Folder
                Rename-Item -Path $FolderPath -NewName $TVShowFolderName
            }
            else {
                $ErrorMessage = "Folder already exists named '$UpdatedFolderPath' `r`n" +
                "Please remove or rename existing folder then rerun the script."
                Write-Error $ErrorMessage -ErrorAction Stop
            }
        }

        # Processes the Season Data in the TV Show Info Results
        $TVShowInfo.seasons
        | Sort-Object season_number
        | ForEach-Object {
            Write-Verbose "Processing Season $("{0:D2}" -f ([int]$_.season_number))"

            # Create Season Folder if it Doesn't Exist with 2-Digit Season Number
            if (-not(
                    Test-Path -Path $(
                        Join-Path -Path $UpdatedFolderPath `
                            -ChildPath $("\Season {0:D2}" -f ([int]$_.season_number))
                    )
                )) {
                New-Item -ItemType Directory -Path $(
                    Join-Path -Path $UpdatedFolderPath `
                        -ChildPath $("\Season {0:D2}" -f ([int]$_.season_number))
                )
            }

            # Define Parameters to be Used in Get-TheMovieDBTVShowSeasonInfo Function
            $Params = @{
                TVShowID     = $TVShowID
                SeasonNumber = $_.season_number
                APIKey       = $TheMovieDB_API
                BaseURL      = $BaseURL
            }
            # Call API to Get Season Info and Processes Data on the Episodes
            (Get-TheMovieDBTVShowSeasonInfo @Params).episodes
            | Sort-Object episode_number
            | ForEach-Object {
                # Creates String for Specifying 2-Digit Season and Episode Numbers
                $FullEpisodeNumber =
                $("S{0:D2}" -f ([int]$_.season_number)) +
                $(if (-not($NoSeparator)) { $Separator }) +
                $("E{0:D2}" -f ([int]$_.episode_number))
                Write-Verbose "Processing Episode $FullEpisodeNumber"

                # Assign Episode Name to Variable
                $EpisodeTitle = $_.name
                Write-Debug "Original Episode Title: $EpisodeTitle"

                # Replace Colon at End of String with a Dash
                $EpisodeTitle = $EpisodeTitle -Replace (': ', ' - ')

                # Replace Colon in Middle of String with Unicode Colon Character
                $EpisodeTitle = $EpisodeTitle -Replace (':', '꞉')

                # Replace Open Parentheses with Dash
                $EpisodeTitle = $EpisodeTitle -Replace (' \(', ' - ')

                # Remove Special Characters Not Supported On Different Operating Systems
                # to Valid Filename Characters.
                $EpisodeTitle = $EpisodeTitle -Replace '[?(){}]'

                # Verify No Invalid Filename Characters in Episode Name
                $EpisodeTitle = $EpisodeTitle -replace "[$InvalidFileNameChars]", ''
                Write-Debug "Filtered Episode Title: $EpisodeTitle"

                # Finds the Correct Episode File by Matching Season & Episode Number
                $videoFiles = Get-ChildItem -Path $UpdatedFolderPath -File -Recurse
                | Where-Object {
                    # Filter results to only contain following video files formats.
                    $_.Extension -in @(
                        '.mkv',
                        '.avi',
                        '.mov',
                        '.wmv',
                        '.mp4',
                        '.m4v',
                        '.mpg',
                        '.mpeg',
                        '.flv'
                    )
                }
                
                # Finds the Correct Episode File by Matching Season & Episode Number
                Find-FileByEpisodeNumber -fileList $videoFiles -FullEpisodeNumber $FullEpisodeNumber
                # Rename the File Found to Correct Name Format
                | ForEach-Object {
                    Write-Verbose "Episode file found: `"$($_.FullName)`""
                    $NewName = (
                        $FormattedTVShowName, $FullEpisodeNumber, $EpisodeTitle -join ' '
                    ) + $($_.extension)
                    # Verify file needs to be renamed.
                    if ($NewName -cne $_.Name ) {
                        Write-Verbose "Renamed Filename: `"$($_.Name)`" to `"$NewName`"."
                        try {
                            Rename-Item -Path $_ -NewName $NewName -ErrorAction Stop -PassThru
                        }
                        catch {
                            Write-Error -Message "Unable to Rename $($_.Name) to $NewName. `n $_"
                        }
                    }
                }
                # Moves File to Correct Season Folder
                | Move-Item -Destination $(
                    Join-Path -Path $UpdatedFolderPath `
                        -ChildPath $(
                        "Season {0:D2}" -f ([int]$FullEpisodeNumber.Substring(1, 2))
                    )
                ) -ErrorAction continue

                # Does the same lookup process as above, this time looking for subtitle files.
                $subtitleList = Get-ChildItem -Path $UpdatedFolderPath -Recurse
                # Filter Results to Ether Directories or Files with Subtitle Files Extensions
                | Where-Object {
                    $_.PSIsContainer -eq $true -or
                    $_.Extension -in @(
                        '.srt',
                        '.smi',
                        '.ssa',
                        '.ass',
                        '.vtt',
                        '.vobsub',
                        '.pgs'
                    )
                }
                # Process Files First so it Doesn't Have Problems with the Folder Subtitle Files Rename Process
                | Sort-Object PSIsContainer
                
                # Grab Result that Matches the Season and Episode Number being Processed
                Find-FileByEpisodeNumber -fileList $subtitleList -FullEpisodeNumber $FullEpisodeNumber
                | ForEach-Object {
                    # Check if Currently ProcessedS Object is a Directory or File
                    if ($_.PSIsContainer) {
                        Write-Verbose "Currently Processing $_.Name Subtitle Directory"
                        # Grab List of Files in that Directory.
                        $_ | Get-ChildItem
                        # Filter out Wrong or Broken Subtitle Files, but keeps 0KB for Testing
                        | Where-Object { $_.Length -eq 0kb -or $_.Length -gt 5kb }
                        | Sort-Object $_.Name
                        | ForEach-Object -Begin { $count = 1 } -Process {
                            # Replace "English" with "en"
                            $SubtitleName = (
                                $_.BaseName.Replace('English', 'en')
                            ) + $(if ($count -gt 1) { ".$count" })
                            # Grabs Episode Name
                            $EpisodeName = ($TVShowInfo.name, $FullEpisodeNumber, $EpisodeTitle -join ' ')
                            # Combines the strings
                            $NewName = ($EpisodeName, $SubtitleName -join '.') + $($_.extension)

                            # Renames the Files Found
                            try {
                                Rename-Item -Path $_ -NewName $NewName -ErrorAction Stop -PassThru
                                Write-Debug "Renamed Subtitle Filename: $NewName"
                            }
                            catch {
                                $Message = "Unable to Rename / Move file to $EpisodeName. `n$_."
                                Write-Error -Message $Message
                            }

                            # Increment Count Counter
                            $count++
                        }
                    }
                    # Results is a file.
                    else {
                        # # Replace "English" with "en"
                        # $SubtitleName = ($_.BaseName.Replace('English','en'))
                        # Grabs Episode Name
                        $EpisodeName = ($TVShowInfo.name, $FullEpisodeNumber, $EpisodeTitle -join ' ')
                        # Assigns the New Name to a Variable
                        $NewName = $EpisodeName + $_.extension

                        # Renames the Files
                        try {
                            Rename-Item -Path $_ -NewName $NewName -ErrorAction Stop -PassThru
                            Write-Debug "Renamed Subtitle File: $NewName"
                        }
                        catch {
                            Write-Error -Message "Unable to Rename $($_.Name) to $NewName. `n $_"
                        }
                    }
                }
                # Moves File to Correct Season Folder
                | Move-Item -Destination $(
                    Join-Path -Path $UpdatedFolderPath `
                        -ChildPath $(
                        "Season {0:D2}" -f ([int]$FullEpisodeNumber.Substring(1, 2))
                    )
                ) -ErrorAction continue
            }
        }
    }

    end {
        # Removes Empty Folders
        Write-Verbose "Remove Empty Folders"
        Remove-EmptyDirectories $UpdatedFolderPath

        # Return Successful Exit Code
        exit 0
    }
}