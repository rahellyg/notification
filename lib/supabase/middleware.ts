import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { protectedPaths, authPaths } from "@/lib/constants";

export async function updateSession(request: NextRequest) {
	let response = NextResponse.next({
		request,
	});

	const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
	const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

	// Avoid crashing the entire middleware on missing env vars in production.
	if (!supabaseUrl || !supabaseAnonKey) {
		console.error(
			"Missing Supabase environment variables for middleware session handling"
		);
		return response;
	}

	const supabase = createServerClient(
		supabaseUrl,
		supabaseAnonKey,
		{
			cookies: {
				getAll() {
					return request.cookies.getAll();
				},
				setAll(cookiesToSet) {
					cookiesToSet.forEach(({ name, value, options }) =>
						request.cookies.set(name, value)
					);
					response = NextResponse.next({
						request,
					});
					cookiesToSet.forEach(({ name, value, options }) =>
						response.cookies.set(name, value, options)
					);
				},
			},
		}
	);

	let user;
	try {
		user = await supabase.auth.getUser();
	} catch (error) {
		console.error("Supabase middleware getUser failed", error);
		return response;
	}
	const url = new URL(request.url);
	const next = url.searchParams.get("next");
	if (user.data.user?.id) {
		if (authPaths.includes(url.pathname)) {
			return NextResponse.redirect(new URL("/", request.url));
		}
		return response;
	} else {
		if (protectedPaths.includes(url.pathname)) {
			return NextResponse.redirect(
				new URL("/auth?next=" + (next || url.pathname), request.url)
			);
		}
		return response;
	}
}
