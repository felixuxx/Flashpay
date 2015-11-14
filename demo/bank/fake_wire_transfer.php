<!DOCTYPE html>
<html>
<head>
<title>Fake Wire Transfer</title>
    <script>
        /*
        @licstart  The following is the entire license notice for the
        JavaScript code in this page.

        Copyright (C) 2014,2015 GNUnet e.V.

        The JavaScript code in this page is free software: you can
        redistribute it and/or modify it under the terms of the GNU
        Lesser General Public License (GNU LGPL) as published by the Free Software
        Foundation, either version 2.1 of the License, or (at your option)
        any later version.  The code is distributed WITHOUT ANY WARRANTY;
        without even the implied warranty of MERCHANTABILITY or FITNESS
        FOR A PARTICULAR PURPOSE.  See the GNU LGPL for more details.

        As additional permission under GNU LGPL version 2.1 section 7, you
        may distribute non-source (e.g., minimized or compacted) forms of
        that code without the copy of the GNU LGPL normally required by
        section 4, provided you include this license notice and a URL
        through which recipients can access the Corresponding Source.

        @licend  The above is the entire license notice
        for the JavaScript code in this page.
        */
    </script>
</head>
<body>
<!-- 
  This page's main aim is to forward the fake wire transfer
  request to the demonstrator and to inform the customer
  about the result.  In a real-world deployment, this
  page would not be required as the customer would do a 
  wire transfer with his bank instead.
  -->
<?php

// Evaluate form
$reserve_pk = $_POST['reserve_pk'];
$kudos_amount = $_POST['kudos_amount'];
$mint = $_POST['mint_rcv'];
echo $mint;
// check if the webform has given a well formed amount
$ret = preg_match ('/[0-9]+(\.[0-9][0-9]?)? [A-Z]+/', $kudos_amount, $matches);
if ($matches[0] != $_POST['kudos_amount'])
{
  http_response_code(400); // BAD REQUEST
  echo "Malformed amount given";
  return;
}
$amount_chunks = preg_split('/[ \.]/', $_POST['kudos_amount']);
$amount_fraction = 0;
if (count($amount_chunks) > 2)
  $amount_fraction = (double) ("0." . $amount_chunks[1]);
$amount_fraction = $amount_fraction * 1000000;
// pack the JSON
$json = json_encode (array ('reserve_pub' => $reserve_pk, 
                            'execution_date' => "/Date(" . time() . ")/",
                            'wire' => array ('type' => 'test'),
                            'amount' => array ('value' => intval($amount_chunks[0]),
	                                       'fraction' => $amount_fraction,
					       'currency' => $amount_chunks[count($amount_chunks) - 1])));

// craft the HTTP request
$req = new http\Client\Request ("POST",
                                "http://" . $mint . "/admin/add/incoming",
			        array ("Content-Type" => "application/json"));
$req->getBody()->append ($json);

// execute HTTP request
$client = new http\Client;
$client->enqueue($req)->send ();
$resp = $client->getResponse ();

// evaluate response
$status_code = $resp->getResponseCode ();
http_response_code ($status_code);

if ($status_code != 200) 
{
  echo "Error $status_code when faking the wire transfer. Please report to taler@gnu.org";
}
else
{
  echo "Pretend wire transfer successful. Exit through the <a href=\"http://toy.taler.net\">gift shop</a> and enjoy shopping!";
}
?>
</body>
</html>
