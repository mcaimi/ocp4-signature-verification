#!/usr/bin/env python3
# signature uploader

from argparse import ArgumentParser, SUPPRESS
import os, sys, re
import base64
import requests
import json

class MalformedArgumentException(Exception):
    def __init__(self, *args, **kwargs):
        super().__init__(self, *args, **kwargs)

class MissingArgumentException(Exception):
    def __init__(self, *args, **kwargs):
        super().__init__(self, *args, **kwargs)

class InvalidPathException(Exception):
    def __init__(self, *args, **kwargs):
        super().__init__(self, *args, **kwargs)

# Parsed options wrapper
class Wrapper():
    def __init__(self, hash_info):
        if not (hash_info.__class__ == dict):
            raise MalformedArgumentException("Parameter class is not Hash, got [%s]" % hash_info.__class__)

        self._wrap(hash_info)

    def _wrap(self, infos):
        for key in infos.keys():
            element = infos.get(key)
            if element.__class__ == dict:
                setattr(self, key, Wrapper(element))
            elif element.__class__ == list:
                setattr(self, key, [])
                embedded_list = getattr(self, key)
                for item in element:
                    embedded_list.append(Wrapper(item))
            else:
                setattr(self, key, element)

    def _split_path(self):
        self.path_components = [ item for item in self.sig_file.split("/")[-3:] ]

    def get_path_components(self):
        self._split_path()
        return self.path_components

    def build_payload(self):
        self._split_path()

        with open(self.sig_file, "rb") as sf:
            self.payload = {
                'repoName': base64.b64encode(self.path_components[0].encode("utf8")).decode("utf8"),
                'layerId': base64.b64encode(self.path_components[1].encode("utf8")).decode("utf8"),
                'signatureData': base64.b64encode(sf.read()).decode()
            }

        return self.payload

ALLOWED_PROTOS = [ "http", "https" ]

# Command Line Options Parser
class Parser():
    def __init__(self):
        self.parser = ArgumentParser(argument_default=SUPPRESS)
        self.parser.add_argument('-r', '--repo_url', dest='repo_url', default="http://signature.apps.kubernetes.local", help="Signature server API endpoint")
        self.parser.add_argument('-a', '--absolute-path', dest='sig_path', help="The *absolute* path to the signature-1 file in the local sigstore")
        self.parser.add_argument('--no-verify', dest='ssl_verify', action='store_false', help="Disables SSL Verification. If not specified, defaults to True")
        self.parser.add_argument('--nexus', dest='upload_to_nexus', action='store_true', help="Uploads to a Nexus3 RAW repository instead. Defaults to False")
        self.parser.add_argument('-u', '--username', dest='username', help="Username to use for authentication if remote server needs it (BasicAuth Only)")
        self.parser.add_argument('-p', '--password', dest='password', help="Password to use for authentication if remote server needs it (BasicAuth Only)")
        self.parser.add_argument('-s', '--sigstore-name', dest='sigstorename', help="RAW Repository name on Nexus to upload to (Nexus Only)")

        self.parser.set_defaults(ssl_verify=True)
        self.parser.set_defaults(upload_to_nexus=False)

        self.parsed_arguments = self.parser.parse_args()

    def _validate_path(self):
        if not os.path.exists(self.parsed_arguments.sig_path):
            raise InvalidPathException("Signature path is invalid.")
        
        setattr(self, 'sig_file', self.parsed_arguments.sig_path)

    def _validate_url(self):
        components = self.parsed_arguments.repo_url.split("://")
        if len(components) < 2:
            raise MalformedArgumentException("URL format is malformed.")

        proto_is_valid = (components[0] in ALLOWED_PROTOS)
        host_validator = re.compile(r"([a-z\d-]{1,63})+", re.IGNORECASE)
        hostname_is_valid = all([ host_validator.match(component) for component in components[1].split(".") ])

        if proto_is_valid and hostname_is_valid:
            setattr(self, 'repo_url', self.parsed_arguments.repo_url)
        else:
            raise InvalidPathException("Unsupported Protocol or Invalid Signature Server Hostname.")

    def parse(self):
        self.wrapper = {}
        if not hasattr(self.parsed_arguments, 'sig_path'):
            raise MissingArgumentException("Missing mandatory option: ABSOLUTE SIGNATURE PATH.")

        try:
            self._validate_url()
        except InvalidPathException as invalid_repo:
            raise InvalidPathException(invalid_repo.__str__())
        except MalformedArgumentException as malformed_arg:
            raise MalformedArgumentException(malformed_arg.__str__())

        try:
            self._validate_path()
        except InvalidPathException as invalid_path:
            raise InvalidPathException(invalid_path.__str__())

        self.wrapper['repo_url'] = self.repo_url
        self.wrapper['sig_file'] = self.sig_file
        self.wrapper['ssl_verify'] = self.parsed_arguments.ssl_verify
        self.wrapper['upload_to_nexus'] = self.parsed_arguments.upload_to_nexus

        if self.parsed_arguments.upload_to_nexus:
            if hasattr(self.parsed_arguments, 'sigstorename'):
                self.wrapper['sigstore_name'] = self.parsed_arguments.sigstorename
            else:
                raise MissingArgumentException("Nexus upload requested, but no sigstore name has been specified.")

            if hasattr(self.parsed_arguments, 'username') and hasattr(self.parsed_arguments, 'password'):
                self.wrapper['username'] = self.parsed_arguments.username
                self.wrapper['password'] = self.parsed_arguments.password

        return Wrapper(self.wrapper)

if __name__ == "__main__":
    oParser = Parser()

    try:
        upload_data = oParser.parse()

        if upload_data.upload_to_nexus:
            params = upload_data.get_path_components()
            nexus_put_url = "%s/repository/%s/%s/%s/signature-1" % (upload_data.repo_url, upload_data.sigstore_name, params[0], params[1])

            print("NEXUS3: Uploading to: %s" % nexus_put_url)

            with open(upload_data.sig_file, 'rb') as signature:
                sigcontents = signature.read()
                if hasattr(upload_data, 'username') and hasattr(upload_data, 'password'):
                    result = requests.put(nexus_put_url, data=sigcontents, auth=requests.auth.HTTPBasicAuth(upload_data.username, upload_data.password), verify=upload_data.ssl_verify)
                else:
                    result = requests.put(nexus_put_url, data=sigcontents, verify=upload_data.ssl_verify)
                print("RESULT STATUS CODE [%s]" % result.status_code)
        else:
            print("UPLOADING TO NGINX")
            
            payload = upload_data.build_payload()
            print("POST to %s [PAYLOAD %s]" % (upload_data.repo_url, payload))
            
            result = requests.post(upload_data.repo_url, data=json.dumps(payload), verify=upload_data.ssl_verify)
            print("RESULT STATUS CODE: [%s]" % result.status_code)
        
        sys.exit(0)
    except MissingArgumentException as missing_argument:
        print(missing_argument)
        sys.exit(1)
    except InvalidPathException as invalid_path:
        print(invalid_path)
        sys.exit(2)
    except MalformedArgumentException as malformed_argument:
        print(malformed_argument)
        sys.exit(3)

