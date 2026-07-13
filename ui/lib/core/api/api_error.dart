import 'package:dio/dio.dart';

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

String apiErrorMessage(Object error) {
  if (error is DioException && error.error is ApiException) {
    return (error.error as ApiException).message;
  }
  if (error is ApiException) {
    return error.message;
  }
  return error.toString();
}
