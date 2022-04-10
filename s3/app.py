"""
SFU CMPT 756
Sample application---book service.
"""

# Standard library modules
import logging
import sys

# Installed packages
from flask import Blueprint
from flask import Flask
from flask import request
from flask import Response

from prometheus_flask_exporter import PrometheusMetrics

import requests

import simplejson as json

# Local modules

# The application

app = Flask(__name__)

metrics = PrometheusMetrics(app)
metrics.info("app_info", "Book process")

db = {
    "name": "http://cmpt756db:30002/api/v1/datastore",
    "endpoint": ["read", "write", "delete"],
}
bp = Blueprint("app", __name__)


@bp.route("/health")
@metrics.do_not_track()
def health():
    return Response("", status=200, mimetype="application/json")


@bp.route("/readiness")
@metrics.do_not_track()
def readiness():
    return Response("", status=200, mimetype="application/json")


@bp.route("/", methods=["GET"])
def list_all():
    headers = request.headers
    # check header here
    if "Authorization" not in headers:
        return Response(
            json.dumps({"error": "missing auth"}),
            status=401,
            mimetype="application/json",
        )
    # list all books here
    return {}


@bp.route("/<book_id>", methods=["GET"])
def get_book(book_id):
    headers = request.headers
    # check header here
    if "Authorization" not in headers:
        return Response(
            json.dumps({"error": "missing auth"}),
            status=401,
            mimetype="application/json",
        )
    payload = {"objtype": "book", "objkey": book_id}
    url = db["name"] + "/" + db["endpoint"][0]
    response = requests.get(
        url, params=payload, headers={"Authorization": headers["Authorization"]}
    )
    return (response.json())


@bp.route("/", methods=["POST"])
def create_book():
    headers = request.headers
    # check header here
    if "Authorization" not in headers:
        return Response(
            json.dumps({"error": "missing auth"}),
            status=401,
            mimetype="application/json",
        )
    try:
        content = request.get_json()
        Author = content["Author"]
        BookTitle = content["BookTitle"]
    except Exception:
        return json.dumps({"message": "error reading arguments"})
    url = db["name"] + "/" + db["endpoint"][1]
    response = requests.post(
        url,
        json={"objtype": "book", "Author": Author, "BookTitle": BookTitle},
        headers={"Authorization": headers["Authorization"]},
    )
    return (response.json())


@bp.route("/<book_id>", methods=["DELETE"])
def delete_book(book_id):
    headers = request.headers
    # check header here
    if "Authorization" not in headers:
        return Response(
            json.dumps({"error": "missing auth"}),
            status=401,
            mimetype="application/json",
        )
    url = db["name"] + "/" + db["endpoint"][2]
    response = requests.delete(
        url,
        params={"objtype": "book", "objkey": book_id},
        headers={"Authorization": headers["Authorization"]},
    )
    return (response.json())


# All database calls will have this prefix.  Prometheus metric
# calls will not---they will have route '/metrics'.  This is
# the conventional organization.
app.register_blueprint(bp, url_prefix="/api/v1/book/")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        logging.error("missing port arg 1")
        sys.exit(-1)

    p = int(sys.argv[1])
    # Do not set debug=True---that will disable the Prometheus metrics
    app.run(host="0.0.0.0", port=p, threaded=True)
