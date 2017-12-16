<#
.Synopsis
   Create AD test enviroment
.DESCRIPTION
    When you need to simulate a real Active Directory with thousands of users you quickly find that creating realistic test accounts is not trivial. 
    Sure enough, you can whip up a quick PowerShell one-liner that creates any number of accounts, but what if you need real first and last names? 
    Real (existing) addresses? Postal codes matching phone area codes? I could go on. The point is that you need two things: input files with names, 
    addresses etc. And script logic that creates user accounts from that data.
#>

function New-ADTestEnviroment
{
    [CmdletBinding()]
    [OutputType([String])]
    Param
    (
        # Domain LDAP Path
        [String]
        $LDAPPath = "DC=company,DC=pri",

        # Ou to create users in
        [String]
        $mainOU = "Company",
              
        # Initial password set for the user
        [String]
        $initialPassword = "User2017.",               

        # This is used to build a user's sAMAccountName
        [String]
        $orgShortName = "COM",                         
        
        # Domain is used for e-mail address and UPN
        [String]
        $dnsDomain = "company.pri",                      
        
        # Used for the user object's company attribute
        [String]
        $company = "Company",  
       
        # How many users to create
        [Int]
        $userCount = 5000,                          

        # How many different offices locations to use 
        [Int]
        $locationCount = 3,                         

        # Files used
        # Format: FirstName
        [String]
        $firstNameFile = "Firstnames.csv", 
                 
        # Format: LastName 
        [String]
        $lastNameFile = "Lastnames.csv",

        # Format: City,Street,State,PostalCode,Country,PhoneNumber  
        [String]            
        $addressFile = "Addresses.csv",  
                             
        # Format: PostalCode,PhoneAreaCode
        [String]
        $postalAreaFile = "PostalAreaCode.txt",

        # Create OUs for each deparment
        [switch]
        $CreateOUs
       
    )

    Begin
    {
        # Departments and associated job titles to assign to the users
        $departments = (                             
                      @{"Name" = "Finance & Accounting"; Positions = ("Manager", "Accountant", "Data Entry")},
                      @{"Name" = "Human Resources"; Positions = ("Manager", "Administrator", "Officer", "Coordinator")},
                      @{"Name" = "Sales"; Positions = ("Manager", "Representative", "Consultant")},
                      @{"Name" = "Marketing"; Positions = ("Manager", "Coordinator", "Assistant", "Specialist")},
                      @{"Name" = "Engineering"; Positions = ("Manager", "Engineer", "Scientist")},
                      @{"Name" = "Consulting"; Positions = ("Manager", "Consultant")},
                      @{"Name" = "IT"; Positions = ("Manager", "Engineer", "Technician")},
                      @{"Name" = "Planning"; Positions = ("Manager", "Engineer")},
                      @{"Name" = "Contracts"; Positions = ("Manager", "Coordinator", "Clerk")},
                      @{"Name" = "Purchasing"; Positions = ("Manager", "Coordinator", "Clerk", "Purchaser")}
                   )

        # Country codes for the countries used in the address file           
        $phoneCountryCodes = @{"US" = "+1"}         

        #
        # Read input files
        #

        Write-Verbose "Importing CSV files..."

        $firstNames = Import-CSV $firstNameFile
        Write-Verbose "-> $($firstNames.Count) Imported Firstnames from $firstNameFile"
      
        $lastNames = Import-CSV $lastNameFile
        Write-Verbose "-> $($lastNames.Count) Imported Lastnames from $lastNameFile"
        
        $addresses = Import-CSV $addressFile
        Write-Verbose "-> $($addresses.Count) Imported Addresses from $addressFile"
        
        Write-Verbose "Creating Password secure string"
        $securePassword = ConvertTo-SecureString $initialPassword -AsPlainText -Force

        # Select the configured number of locations from the address list
        Write-Verbose "Generating locations Hash Table"
        $locations = @()
        $addressIndexesUsed = @()
        for ($i = 0; $i -le $locationCount; $i++)
        {
           # Determine a random address
           $addressIndex = -1
           do
           {
              $addressIndex = Get-Random -Minimum 0 -Maximum $addresses.Count
           } while ($addressIndexesUsed -contains $addressIndex)
   
           # Store the address in a location variable
           $street = $addresses[$addressIndex].Street
           $city = $addresses[$addressIndex].City
           $state = $addresses[$addressIndex].State
           $postalCode = $addresses[$addressIndex].PostalCode
           $country = $addresses[$addressIndex].Country
           $phoneNumber = $addresses[$addressIndex].PhoneNumber
           $locations += @{"Street" = $street; "City" = $city; "State" = $state; "PostalCode" = $postalCode; "Country" = $country; "PhoneNumber" = $phoneNumber}

           # Do not use this address again
           $addressIndexesUsed += $addressIndex
        }
    }

    Process
    {
        if ($CreateOUs -and $pscmdlet.ShouldProcess($dnsDomain, "Create OUs"))
        {
            #Create Main OU
            try
            {
                New-ADOrganizationalUnit -Name $mainOU -ProtectedFromAccidentalDeletion $false
                Write-Verbose "$mainOU OU created"
            }
            catch [Microsoft.ActiveDirectory.Management.ADException]
            {
                Write-Warning "$mainOU OU already exists"
            }
            catch {
                Write-Error "Error while creating $mainOU OU"
            }

            #Create sub OUs
            foreach($deparment in $departments){
                try
                {
                    New-ADOrganizationalUnit -Name $deparment.Name -Path "OU=$mainOU,$LDAPPath" -ProtectedFromAccidentalDeletion $false
                    Write-Verbose "$($deparment.Name) OU created"
                }
                catch [Microsoft.ActiveDirectory.Management.ADException]
                {
                    Write-Warning "$($deparment.Name) OU already exists"
                }
                catch {
                    Write-Error "Error while creating $($deparment.Name) OU"
                }
            }
        }

        if ($pscmdlet.ShouldProcess($dnsDomain, "Create Users"))
        {
            #create users
            for ($accountIndex = 1; $accountIndex -le $userCount; $accountIndex++)
            {
                $FnameIndex = Get-Random -Minimum 0 -Maximum $firstNames.Count
                $LnameIndex = Get-Random -Minimum 0 -Maximum $lastnames.Count

                $Fname = $firstNames[$FnameIndex].Firstname
                $Lname = $lastNames[$LnameIndex].Lastname

                $displayName = $Fname + " " + $Lname

                # Address
                $locationIndex = Get-Random -Minimum 0 -Maximum $locations.Count
                $street = $locations[$locationIndex].Street
                $city = $locations[$locationIndex].City
                $state = $locations[$locationIndex].State
                $postalCode = $locations[$locationIndex].PostalCode
                $country = $locations[$locationIndex].Country
                $phoneNumber = $locations[$locationIndex].PhoneNumber
                $officePhone = "$phoneNumber x$($accountIndex.ToString().PadLeft($userCount.ToString().Length,"0"))"
   
                # Department & title
                $departmentIndex = Get-Random -Minimum 0 -Maximum $departments.Count
                $department = $departments[$departmentIndex].Name
                $title = $departments[$departmentIndex].Positions[$(Get-Random -Minimum 0 -Maximum $departments[$departmentIndex].Positions.Count)]
   
                # Build the sAMAccountName: $orgShortName + employee number
                $sAMAccountName = $orgShortName + $accountIndex

                # User OU
                $userPath = "OU=$mainOU,$LDAPPath"
                if($CreateOUs) {
                    $userPath = "OU=$department,$userPath"
                }

                # Create the user account
                Try { 
                    New-ADUser -SamAccountName $sAMAccountName -Name $displayName -Path $userPath -AccountPassword $securePassword -Enabled $true -GivenName $Fname -Surname $Lname -DisplayName $displayName -EmailAddress "$Fname.$Lname@$dnsDomain" -StreetAddress $street -City $city -PostalCode $postalCode -State $state -Country $country -UserPrincipalName "$sAMAccountName@$dnsDomain" -Company $company -Department $department -EmployeeNumber $accountIndex -Title $title -OfficePhone $officePhone
                    Write-Verbose "Created user # $accountIndex ,$displayName, $sAMAccountName, $title, $department, $street, $city"
                } 
                Catch [Microsoft.ActiveDirectory.Management.ADIdentityAlreadyExistsException]
                {
                    Write-Verbose "Account $sAMAccountName already exist"
                    $accountIndex--
                }
            }
        }
    }

    End
    {
        Write-Verbose "Completed setup, $userCount users created"
    }
}

New-ADTestEnviroment -Verbose -CreateOUs