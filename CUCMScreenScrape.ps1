##This Script pulls data from the CUCM Exterprise Paramaters screen, REST and SOAP are better ways to do this but this may solve a need


##If you have not lowered you execution level, highlight the following line and execute this, then the script will run

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass


##This removes certificate issues if you don't have a PKI or you don't trust the server cert on CUCM

add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy


##The following line forces support for TLS1.2


[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::TLS12




##sets environment variables

cd $PSScriptRoot
$CredObject = import-csv ".\cucmcredentials.txt"
$CUCMusername = $CredObject.username
$CUCMpassword = $CredObject.password
$CUCMserver = $CredObject.server.ToString()

$CUCMcred = New-Object System.Management.Automation.PSCredential($CUCMusername,($CUCMpassword | ConvertTo-SecureString -asPlainText -Force))

$CUCMpair = "${CUCMusername}:${CUCMpassword}"
$bytes = [System.Text.Encoding]::ASCII.GetBytes($CUCMpair)
$base64 = [System.Convert]::ToBase64String($bytes)
$basicAuthValue = "Basic $base64"
$headers = @{ Authorization = $basicAuthValue }


##Login paramaters for CUCM, the username and password are j_ for some reason


## URL is the URL you want to scrape
$URL = "https://$CUCMServer/ccmadmin/enterpriseParamEdit.do?service=11"

##This URL is the base CUCM page used to create a connection and get the cookies and webauth
$URLlogin ="https://$CUCMServer/ccmadmin/"



##This will load the base page, I tried without the initial load but the page would not allow login
##This places the sessin variables in the Global context variable, probably not needed but should allow all PS scripts access if needed
$resultslogin = Invoke-WebRequest -Uri $URLlogin -SessionVariable Global:CUCMSession


##This creates the login details for the CUCM webpage, the username and password are j_ for some reason this is on the login page
$form =$resultslogin.Forms[0]
$form.fields['j_username'] = $CUCMusername.ToString()
$form.fields['j_password'] = $CUCMpassword.ToString()

##Performs the login
$resultslogin = Invoke-WebRequest -Uri ($URLlogin + $form.Action) -WebSession $Global:CUCMSession -Method POST -Body $form.Fields


##After login this loads the webpage you actually wanted to scrape but uses the session variables
$results = Invoke-WebRequest -Uri $URL -Method Get -WebSession $Global:CUCMSession

##This outputs the whole object (only the body of the webpage) to the console, this is long
##I believe that the ParsedHTML item is only in PS V5.0 or later
$results.ParsedHtml.body

##This sets the class identifier to filter the massive reply from the webpage, you need to use the inspect right click on chrome or view the HTML code
##There are other options but this seemed the easist

$classname = 'ClusterID'
##HTML CODE EXTRACT

### <input type="text" name="serviceParameters[0].fieldValue" size="50" value="StandAloneCluster" id="ClusterID" class="ClusterID" style="width: 30em" 
### onchange=" validateStringRule(this , 'Cluster ID','^[0-9a-zA-Z.-]*$','50',false,false,'Restart all services for the parameter change to take effect.
### ','Provide a valid cluster Id that comprises of (A-Z,a-z,0-9,.,-)','false');">



$results.ParsedHtml.body.getElementsByClassName($classname)  | out-file .\FilteredResults.txt


##Additional Data
    $results.ParsedHtml.body.getElementsByClassName("URLAuthentication")

    $ClusterName    = $results.ParsedHtml.body.getElementsByClassName($classname) | select value
    $AuthURL     = $results.ParsedHtml.body.getElementsByClassName("URLAuthentication") | select value
    $TopLevelDomain  = $results.ParsedHtml.body.getElementsByClassName("OrganizationDomain") | select value
    $DDOSSetting= $results.ParsedHtml.body.getElementsByClassName("DoSProtectionFlag") | select value
                                 
                     

##Creates Custom Object and then outputs to a table, you could use the out-file to send to a file or exprt-csv
$MyCustomObject = New-Object PSObject 
Add-Member -InputObject $MyCustomObject -MemberType NoteProperty -Name ClusterName -Value $ClusterName.value
Add-Member -InputObject $MyCustomObject -MemberType NoteProperty -Name AuthURL -Value $AuthURL.value
Add-Member -InputObject $MyCustomObject -MemberType NoteProperty -Name TopLevelDomain -Value $TopLevelDomain.value
Add-Member -InputObject $MyCustomObject -MemberType NoteProperty -Name DDOS -Value $DDOSSetting.value

$MyCustomObject | select 'ClusterName','AuthURL','TopLevelDomain', 'DDOS' | ft